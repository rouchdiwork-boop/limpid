import 'dart:convert';

import 'package:limpid_api/src/auth/auth_middleware.dart';
import 'package:limpid_api/src/config/app_config.dart';
import 'package:limpid_api/src/db/audit_entry.dart';
import 'package:limpid_api/src/db/in_memory_team_database.dart';
import 'package:limpid_api/src/db/in_memory_team_invitation_store.dart';
import 'package:limpid_api/src/db/team_database.dart';
import 'package:limpid_api/src/db/team_invitation_record.dart';
import 'package:limpid_api/src/logging/logger.dart';
import 'package:limpid_api/src/middleware/error_handler.dart';
import 'package:limpid_api/src/routes/team_routes.dart';
import 'package:limpid_api/src/services/mailer.dart';
import 'package:limpid_api/src/services/team_service.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';
import 'package:test/test.dart';

import 'helpers/test_server.dart';

/// La réponse décodée de l'API des équipes.
final class Answer {
  /// Crée une réponse décodée.
  const Answer(this.statusCode, this.body);

  /// Le code de statut HTTP.
  final int statusCode;

  /// Le corps JSON de la réponse.
  final Map<String, dynamic> body;

  /// La charge utile de la réponse.
  Map<String, dynamic> get data => body['data'] as Map<String, dynamic>;

  /// La liste de la réponse.
  List<dynamic> get items => body['data'] as List<dynamic>;

  /// L'erreur de la réponse.
  Map<String, dynamic> get error => body['error'] as Map<String, dynamic>;
}

/// Un port de courriel qui garde les messages.
///
/// Le test choisit le mode : configuré — le lien part et n'est plus rendu —
/// ou journal — le lien est rendu une seule fois.
final class RecordingMailer implements Mailer {
  /// Crée un port.
  RecordingMailer({this.configured = true});

  /// Le fournisseur est-il configuré.
  final bool configured;

  /// Les messages envoyés.
  final List<TeamInvitationMail> mails = <TeamInvitationMail>[];

  @override
  bool get isConfigured => configured;

  @override
  Future<void> sendTeamInvitation(TeamInvitationMail mail) async {
    mails.add(mail);
  }
}

/// L'API des invitations d'équipe, servie en mémoire.
///
/// Le serveur est un routeur réel : les erreurs métier deviennent des
/// réponses HTTP comme en production.
final class InvitationApi {
  InvitationApi._(this._handler, this.invitations, this.audit, this.mailer);

  final Handler _handler;

  /// Le magasin des invitations en attente.
  final InMemoryTeamInvitationStore invitations;

  /// Le journal d'audit.
  final InMemoryAuditLog audit;

  /// Le port du courriel.
  final RecordingMailer mailer;

  /// Démarre l'API sur une base en mémoire.
  ///
  /// [mailConfigured] dit si le fournisseur de courriel est configuré : sans
  /// lui, la route rend le lien une seule fois.
  static InvitationApi start({
    PlanLookup? planLookup,
    DateTime Function()? clock,
    bool mailConfigured = false,
    int rateLimitCapacity = teamInvitationRateLimitCapacity,
  }) {
    final InMemoryTeamInvitationStore invitations =
        InMemoryTeamInvitationStore();
    final InMemoryTeamDatabase database = InMemoryTeamDatabase(
      planLookup: planLookup,
      invitations: invitations,
    );
    final InMemoryAuditLog audit = InMemoryAuditLog();
    final RecordingMailer mailer = RecordingMailer(configured: mailConfigured);
    final Router router = Router();
    registerTeamRoutes(
      router,
      database,
      _config(),
      audit: audit,
      invitations: invitations,
      mailer: mailer,
      clock: clock,
      invitationRateLimitCapacity: rateLimitCapacity,
    );
    final Logger logger = Logger(
      level: LogLevel.warning,
      sink: (String line) {},
    );
    return InvitationApi._(
      errorHandlerMiddleware(logger: logger)(router.call),
      invitations,
      audit,
      mailer,
    );
  }

  /// Envoie une requête authentifiée et décode la réponse.
  Future<Answer> send(
    String method,
    String path, {
    String userId = 'owner-1',
    String email = '',
    Map<String, Object?>? body,
  }) async {
    final Request request = Request(
      method,
      Uri.parse('http://localhost$path'),
      headers: body == null
          ? null
          : <String, Object>{'content-type': 'application/json'},
      body: body == null ? null : jsonEncode(body),
      context: <String, Object>{
        authContextKey: AuthContext(
          userId: userId,
          email: email,
          claims: const <String, dynamic>{},
        ),
      },
    );
    final Response response = await _handler(request);
    final String raw = await response.readAsString();
    return Answer(response.statusCode, jsonDecode(raw) as Map<String, dynamic>);
  }

  /// La configuration minimale du serveur de test.
  static AppConfig _config() {
    return AppConfig.fromEnvironment(<String, String>{
      'PORT': '0',
      'SUPABASE_URL': 'https://project.test',
      'LOG_LEVEL': 'warning',
    });
  }
}

/// La formule « Studio » : cinq sièges par équipe.
Future<String?> _studioPlan(String userId) async => 'studio';

/// Crée une équipe et renvoie son identifiant.
Future<String> _createTeam(InvitationApi api) async {
  final Answer created = await api.send(
    'POST',
    '/v1/teams',
    body: <String, Object?>{'name': 'La Brigade'},
  );
  return created.data['id'] as String;
}

/// Invite l'adresse [email] dans l'équipe [teamId].
Future<Answer> _inviteByEmail(
  InvitationApi api,
  String teamId, {
  String email = 'invite@example.com',
  String role = 'coAuthor',
  String callerId = 'owner-1',
  int? expiresInHours,
}) {
  return api.send(
    'POST',
    '/v1/teams/$teamId/invitations',
    userId: callerId,
    body: <String, Object?>{
      'email': email,
      'role': role,
      'expires_in_hours': ?expiresInHours,
    },
  );
}

/// Le jeton que la réponse de création porte.
String _tokenOf(Answer answer) {
  final String link = answer.data['invitation_link'] as String;
  return link.split('/').elementAt(link.split('/').length - 2);
}

void main() {
  group('invitation par courriel', () {
    late InvitationApi api;

    setUp(() {
      api = InvitationApi.start(planLookup: _studioPlan);
    });

    test('attend : le membre n\'entre pas dans l\'équipe', () async {
      final String teamId = await _createTeam(api);

      final Answer invited = await _inviteByEmail(api, teamId);

      expect(invited.statusCode, 201);
      expect(invited.data['status'], 'pending');
      expect(invited.data['email'], 'invite@example.com');
      expect(invited.data['role'], 'coAuthor');
      expect(invited.data['expires_at'], isNotNull);
      expect(invited.data['accepted_at'], isNull);

      final Answer members = await api.send('GET', '/v1/teams/$teamId/members');
      expect(members.items, hasLength(1));

      final Answer listed = await api.send(
        'GET',
        '/v1/teams/$teamId/invitations',
      );
      expect(listed.statusCode, 200);
      expect(listed.items, hasLength(1));
      expect(
        (listed.items.first as Map<String, dynamic>)['email'],
        'invite@example.com',
      );
    });

    test('normalise l\'adresse invitée', () async {
      final String teamId = await _createTeam(api);

      final Answer invited = await _inviteByEmail(
        api,
        teamId,
        email: '  Alice@Exemple.COM ',
      );

      expect(invited.statusCode, 201);
      expect(invited.data['email'], 'alice@exemple.com');
    });

    test('refuse une adresse invalide', () async {
      final String teamId = await _createTeam(api);

      final Answer invited = await _inviteByEmail(
        api,
        teamId,
        email: 'pas-une',
      );

      expect(invited.statusCode, 400);
      expect(invited.error['code'], 'validation_failed');
    });

    test('le lien n\'est rendu que sans fournisseur de courriel', () async {
      final String teamId = await _createTeam(api);

      final Answer rendered = await _inviteByEmail(api, teamId);
      expect(rendered.data['invitation_link'], isNotNull);

      final InvitationApi journal = InvitationApi.start(
        planLookup: _studioPlan,
        mailConfigured: true,
      );
      final String otherTeam = await _createTeam(journal);
      final Answer sent = await _inviteByEmail(journal, otherTeam);
      expect(sent.data.containsKey('invitation_link'), isFalse);
      expect(journal.mailer.mails, hasLength(1));
      expect(journal.mailer.mails.single.link, contains('/accept'));
    });

    test('n\'accepte pas deux fois la même adresse', () async {
      final String teamId = await _createTeam(api);
      await _inviteByEmail(api, teamId);

      final Answer again = await _inviteByEmail(api, teamId);

      expect(again.statusCode, 409);
    });

    test('le propriétaire seul invite', () async {
      final String teamId = await _createTeam(api);
      await api.send(
        'POST',
        '/v1/teams/$teamId/invitations',
        userId: 'owner-1',
        body: <String, Object?>{'user_id': 'member-1', 'role': 'coAuthor'},
      );

      final Answer invited = await _inviteByEmail(
        api,
        teamId,
        callerId: 'member-1',
      );

      expect(invited.statusCode, 403);
      expect(invited.error['code'], 'forbidden');
    });

    test('trace l\'invitation dans le journal d\'audit', () async {
      final String teamId = await _createTeam(api);

      await _inviteByEmail(api, teamId);

      final List<AuditEntry> entries = api.audit.entries;
      expect(entries, isNotEmpty);
      expect(entries.last.action, 'team.email_invitation_sent');
      expect(entries.last.targetId, teamId);
      expect(entries.last.metadata.containsKey('email'), isFalse);
    });
  });

  group('acceptation de l\'invitation', () {
    late InvitationApi api;

    setUp(() {
      api = InvitationApi.start(planLookup: _studioPlan);
    });

    test('ajoute le membre avec le rôle de l\'invitation', () async {
      final String teamId = await _createTeam(api);
      final Answer invited = await _inviteByEmail(
        api,
        teamId,
        role: 'betaReader',
      );
      final String token = _tokenOf(invited);

      final Answer accepted = await api.send(
        'POST',
        '/v1/team-invitations/$token/accept',
        userId: 'member-1',
        email: 'invite@example.com',
      );

      expect(accepted.statusCode, 200);
      expect(accepted.data['status'], 'accepted');
      expect(accepted.data['accepted_by'], 'member-1');

      final Answer members = await api.send('GET', '/v1/teams/$teamId/members');
      expect(members.items, hasLength(2));
      expect(
        (members.items.last as Map<String, dynamic>)['role'],
        'betaReader',
      );
    });

    test('un jeton inconnu est un 404', () async {
      final Answer accepted = await api.send(
        'POST',
        '/v1/team-invitations/lt.00000000000000000000000000.peu-importe/accept',
        userId: 'member-1',
        email: 'invite@example.com',
      );

      expect(accepted.statusCode, 404);
      expect(accepted.error['code'], 'not_found');
    });

    test('une adresse qui ne correspond pas est un 404', () async {
      final String teamId = await _createTeam(api);
      final Answer invited = await _inviteByEmail(api, teamId);
      final String token = _tokenOf(invited);

      final Answer accepted = await api.send(
        'POST',
        '/v1/team-invitations/$token/accept',
        userId: 'member-2',
        email: 'autre@example.com',
      );

      expect(accepted.statusCode, 404);
      expect(accepted.error['code'], 'not_found');

      final Answer members = await api.send('GET', '/v1/teams/$teamId/members');
      expect(members.items, hasLength(1));
    });

    test('une invitation expirée n\'est pas acceptée', () async {
      DateTime now = DateTime.utc(2026, 11, 1);
      final InvitationApi clocked = InvitationApi.start(
        planLookup: _studioPlan,
        clock: () => now,
      );
      final String teamId = await _createTeam(clocked);
      final Answer invited = await _inviteByEmail(
        clocked,
        teamId,
        expiresInHours: 1,
      );
      final String token = _tokenOf(invited);

      now = now.add(const Duration(hours: 2));

      final Answer accepted = await clocked.send(
        'POST',
        '/v1/team-invitations/$token/accept',
        userId: 'member-1',
        email: 'invite@example.com',
      );

      expect(accepted.statusCode, 404);
      final Answer members = await clocked.send(
        'GET',
        '/v1/teams/$teamId/members',
      );
      expect(members.items, hasLength(1));
    });

    test('une invitation révoquée n\'est pas acceptée', () async {
      final String teamId = await _createTeam(api);
      final Answer invited = await _inviteByEmail(api, teamId);
      final String token = _tokenOf(invited);
      final String invitationId = invited.data['id'] as String;

      final Answer revoked = await api.send(
        'DELETE',
        '/v1/teams/$teamId/invitations/$invitationId',
      );
      expect(revoked.statusCode, 200);
      expect(revoked.data['status'], 'revoked');

      final Answer accepted = await api.send(
        'POST',
        '/v1/team-invitations/$token/accept',
        userId: 'member-1',
        email: 'invite@example.com',
      );

      expect(accepted.statusCode, 404);
    });

    test('une invitation déjà acceptée ne se réactive pas', () async {
      final String teamId = await _createTeam(api);
      final Answer invited = await _inviteByEmail(api, teamId);
      final String token = _tokenOf(invited);

      final Answer accepted = await api.send(
        'POST',
        '/v1/team-invitations/$token/accept',
        userId: 'member-1',
        email: 'invite@example.com',
      );
      expect(accepted.statusCode, 200);

      final Answer again = await api.send(
        'POST',
        '/v1/team-invitations/$token/accept',
        userId: 'member-1',
        email: 'invite@example.com',
      );
      expect(again.statusCode, 404);

      // Une nouvelle invitation est un nouvel objet, avec un nouveau jeton.
      final Answer fresh = await _inviteByEmail(api, teamId);
      final String newToken = _tokenOf(fresh);
      expect(newToken, isNot(token));

      final Answer acceptedAgain = await api.send(
        'POST',
        '/v1/team-invitations/$newToken/accept',
        userId: 'member-2',
        email: 'invite@example.com',
      );
      expect(acceptedAgain.statusCode, 200);
    });

    test('le siège est vérifié à l\'acceptation', () async {
      String plan = 'studio';
      final InvitationApi changing = InvitationApi.start(
        planLookup: (String userId) async => plan,
      );
      final String teamId = await _createTeam(changing);
      await changing.send(
        'POST',
        '/v1/teams/$teamId/invitations',
        body: <String, Object?>{'user_id': 'member-1', 'role': 'coAuthor'},
      );
      final Answer invited = await _inviteByEmail(changing, teamId);
      final String token = _tokenOf(invited);

      // La formule a changé entre l'invitation et la réponse : le compte
      // n'a plus de siège pour l'invité.
      plan = 'free';

      final Answer accepted = await changing.send(
        'POST',
        '/v1/team-invitations/$token/accept',
        userId: 'member-2',
        email: 'invite@example.com',
      );

      expect(accepted.statusCode, 402);
      expect(accepted.error['code'], 'plan_limit_reached');

      final Answer members = await changing.send(
        'GET',
        '/v1/teams/$teamId/members',
      );
      expect(members.items, hasLength(2));
    });

    test('trace l\'acceptation dans le journal d\'audit', () async {
      final String teamId = await _createTeam(api);
      final Answer invited = await _inviteByEmail(api, teamId);
      final String token = _tokenOf(invited);

      await api.send(
        'POST',
        '/v1/team-invitations/$token/accept',
        userId: 'member-1',
        email: 'invite@example.com',
      );

      final List<AuditEntry> entries = api.audit.entries;
      expect(entries.last.action, 'team.email_invitation_accepted');
      expect(entries.last.userId, 'member-1');
    });
  });

  group('secret de l\'invitation', () {
    late InvitationApi api;

    setUp(() {
      api = InvitationApi.start(planLookup: _studioPlan);
    });

    test('la base ne garde que l\'empreinte du jeton', () async {
      final String teamId = await _createTeam(api);
      final Answer invited = await _inviteByEmail(api, teamId);
      final String token = _tokenOf(invited);
      final String invitationId = invited.data['id'] as String;

      final TeamInvitationRecord? record = await api.invitations.findById(
        invitationId,
      );

      expect(record, isNotNull);
      expect(record!.tokenHash, isNot(token));
      expect(record.tokenHash, hashTeamInvitationToken(token));
      expect(record.tokenHash.length, 64);
      expect(
        <String?>[
          record.tokenHash,
          record.email,
          record.id,
          record.teamId,
          record.role.name,
          record.status.name,
        ].join(' '),
        isNot(contains(token)),
      );
    });

    test('la liste des invitations ne rend aucun jeton', () async {
      final String teamId = await _createTeam(api);
      final Answer invited = await _inviteByEmail(api, teamId);
      final String token = _tokenOf(invited);

      final Answer listed = await api.send(
        'GET',
        '/v1/teams/$teamId/invitations',
      );

      expect(listed.items.first.containsKey('token'), isFalse);
      expect(listed.items.first.containsKey('token_hash'), isFalse);
      expect(jsonEncode(listed.items), isNot(contains(token)));
    });
  });

  group('limitation de débit', () {
    test('la création est limitée en débit', () async {
      final InvitationApi api = InvitationApi.start(
        planLookup: _studioPlan,
        rateLimitCapacity: 2,
      );
      final String teamId = await _createTeam(api);

      final Answer first = await _inviteByEmail(api, teamId, email: 'a@b.co');
      expect(first.statusCode, 201);
      final Answer second = await _inviteByEmail(api, teamId, email: 'c@d.co');
      expect(second.statusCode, 201);

      final Answer third = await _inviteByEmail(api, teamId, email: 'e@f.co');
      expect(third.statusCode, 429);
      expect(third.error['code'], 'rate_limited');
    });
  });
}
