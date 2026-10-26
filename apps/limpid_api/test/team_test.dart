import 'dart:convert';
import 'dart:io';

import 'package:limpid_api/src/auth/auth_middleware.dart';
import 'package:limpid_api/src/config/app_config.dart';
import 'package:limpid_api/src/db/in_memory_team_database.dart';
import 'package:limpid_api/src/db/sqlite_database.dart';
import 'package:limpid_api/src/db/sqlite_statement_splitter.dart';
import 'package:limpid_api/src/db/sqlite_team_database.dart';
import 'package:limpid_api/src/db/team_database.dart';
import 'package:limpid_api/src/logging/logger.dart';
import 'package:limpid_api/src/middleware/error_handler.dart';
import 'package:limpid_api/src/routes/team_routes.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';
import 'package:test/test.dart';

/// La migration SQLite des équipes.
const String _teamMigration = 'db/migrations/sqlite/0009_teams.sql';

/// Applique la migration des équipes à [database].
Future<void> _applyTeamMigration(SqliteDatabase database) async {
  final String script = await File(_teamMigration).readAsString();
  const SqlStatementSplitter splitter = SqlStatementSplitter();
  await database.run(() {
    for (final String statement in splitter.split(script)) {
      database.connection.execute(statement);
    }
  });
}

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

/// L'API des équipes, servie en mémoire.
///
/// Le serveur est un routeur réel : les erreurs métier deviennent des
/// réponses HTTP comme en production.
final class TeamApi {
  TeamApi._(this._handler);

  final Handler _handler;

  /// Démarre l'API sur une base en mémoire.
  ///
  /// [planLookup] lit la formule du compte ; à défaut, le compte est traité
  /// comme « Gratuit ». [database] remplace la base en mémoire par une autre
  /// implémentation du port.
  static TeamApi start({PlanLookup? planLookup, TeamDatabase? database}) {
    final TeamDatabase teams =
        database ?? InMemoryTeamDatabase(planLookup: planLookup);
    final Router router = Router();
    registerTeamRoutes(router, teams, _config());
    final Logger logger = Logger(
      level: LogLevel.warning,
      sink: (String line) {},
    );
    return TeamApi._(errorHandlerMiddleware(logger: logger)(router.call));
  }

  /// Envoie une requête authentifiée par [userId] et décode la réponse.
  Future<Answer> send(
    String method,
    String path, {
    String userId = 'owner-1',
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
          email: '',
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
Future<String> _createTeam(TeamApi api, {String userId = 'owner-1'}) async {
  final Answer created = await api.send(
    'POST',
    '/v1/teams',
    userId: userId,
    body: <String, Object?>{'name': 'La Brigade'},
  );
  return created.data['id'] as String;
}

/// Invite [userId] dans l'équipe [teamId] avec le rôle [role].
Future<Answer> _invite(
  TeamApi api,
  String teamId, {
  required String userId,
  String role = 'coAuthor',
  String callerId = 'owner-1',
}) {
  return api.send(
    'POST',
    '/v1/teams/$teamId/invitations',
    userId: callerId,
    body: <String, Object?>{'user_id': userId, 'role': role},
  );
}

void main() {
  group('cycle de vie des équipes', () {
    late TeamApi api;

    setUp(() {
      api = TeamApi.start(planLookup: _studioPlan);
    });

    test('crée une équipe dont le créateur est le propriétaire', () async {
      final Answer created = await api.send(
        'POST',
        '/v1/teams',
        body: <String, Object?>{'name': 'La Brigade'},
      );

      expect(created.statusCode, 201);
      expect(created.data['name'], 'La Brigade');
      expect(created.data['owner_id'], 'owner-1');

      final Answer listed = await api.send('GET', '/v1/teams');
      expect(listed.statusCode, 200);
      expect(listed.items, hasLength(1));

      final Answer members = await api.send(
        'GET',
        '/v1/teams/${created.data['id']}/members',
      );
      expect(members.statusCode, 200);
      expect(members.items, hasLength(1));
      expect((members.items.first as Map<String, dynamic>)['role'], 'owner');
    });

    test('invite un co-auteur et le compte parmi les membres', () async {
      final String teamId = await _createTeam(api);

      final Answer invited = await _invite(api, teamId, userId: 'member-1');

      expect(invited.statusCode, 201);
      expect(invited.data['user_id'], 'member-1');
      expect(invited.data['role'], 'coAuthor');
      expect(invited.data['invited_by'], 'owner-1');

      final Answer members = await api.send('GET', '/v1/teams/$teamId/members');
      expect(members.items, hasLength(2));
    });

    test('change le rôle d\'un membre', () async {
      final String teamId = await _createTeam(api);
      await _invite(api, teamId, userId: 'member-1');

      final Answer patched = await api.send(
        'PATCH',
        '/v1/teams/$teamId/members/member-1',
        body: <String, Object?>{'role': 'betaReader'},
      );

      expect(patched.statusCode, 200);
      expect(patched.data['role'], 'betaReader');
    });

    test('le propriétaire retire un membre', () async {
      final String teamId = await _createTeam(api);
      await _invite(api, teamId, userId: 'member-1');

      final Answer removed = await api.send(
        'DELETE',
        '/v1/teams/$teamId/members/member-1',
      );

      expect(removed.statusCode, 200);
      expect(removed.data['removed'], isTrue);

      final Answer members = await api.send('GET', '/v1/teams/$teamId/members');
      expect(members.items, hasLength(1));
    });

    test('un membre quitte l\'équipe lui-même', () async {
      final String teamId = await _createTeam(api);
      await _invite(api, teamId, userId: 'member-1');

      final Answer left = await api.send(
        'DELETE',
        '/v1/teams/$teamId/members/member-1',
        userId: 'member-1',
      );

      expect(left.statusCode, 200);

      final Answer members = await api.send('GET', '/v1/teams/$teamId/members');
      expect(members.items, hasLength(1));
    });

    test('le propriétaire supprime l\'équipe', () async {
      final String teamId = await _createTeam(api);

      final Answer deleted = await api.send('DELETE', '/v1/teams/$teamId');

      expect(deleted.statusCode, 200);
      expect(deleted.data['deleted'], isTrue);

      final Answer members = await api.send('GET', '/v1/teams/$teamId/members');
      expect(members.statusCode, 404);
      expect(members.error['code'], 'not_found');
    });
  });

  group('autorisations', () {
    late TeamApi api;

    setUp(() {
      api = TeamApi.start(planLookup: _studioPlan);
    });

    test('un co-auteur ne peut pas inviter', () async {
      final String teamId = await _createTeam(api);
      await _invite(api, teamId, userId: 'member-1');

      final Answer response = await _invite(
        api,
        teamId,
        userId: 'member-2',
        callerId: 'member-1',
      );

      expect(response.statusCode, 403);
      expect(response.error['code'], 'forbidden');
    });

    test('un co-auteur ne peut pas changer un rôle', () async {
      final String teamId = await _createTeam(api);
      await _invite(api, teamId, userId: 'member-1');

      final Answer response = await api.send(
        'PATCH',
        '/v1/teams/$teamId/members/member-1',
        userId: 'member-1',
        body: <String, Object?>{'role': 'reader'},
      );

      expect(response.statusCode, 403);
      expect(response.error['code'], 'forbidden');
    });

    test('un compte étranger ne voit pas l\'équipe', () async {
      final String teamId = await _createTeam(api);

      final Answer response = await api.send(
        'GET',
        '/v1/teams/$teamId/members',
        userId: 'etranger',
      );

      expect(response.statusCode, 404);
      expect(response.error['code'], 'not_found');
    });

    test('une équipe inconnue répond 404, jamais 403', () async {
      final Answer response = await api.send(
        'GET',
        '/v1/teams/equipe-inconnue/members',
      );

      expect(response.statusCode, 404);
      expect(response.error['code'], 'not_found');
    });

    test('le propriétaire ne peut pas quitter son équipe', () async {
      final String teamId = await _createTeam(api);

      final Answer response = await api.send(
        'DELETE',
        '/v1/teams/$teamId/members/owner-1',
      );

      expect(response.statusCode, 409);
      expect(response.error['code'], 'conflict');
    });

    test('le rôle du propriétaire ne peut pas être modifié', () async {
      final String teamId = await _createTeam(api);

      final Answer response = await api.send(
        'PATCH',
        '/v1/teams/$teamId/members/owner-1',
        body: <String, Object?>{'role': 'reader'},
      );

      expect(response.statusCode, 409);
      expect(response.error['code'], 'conflict');
    });
  });

  group('sièges', () {
    test(
      'la cinquième invitation passe, la sixième est refusée et nomme la limite',
      () async {
        final TeamApi api = TeamApi.start(planLookup: _studioPlan);
        final String teamId = await _createTeam(api);

        for (var index = 1; index <= 5; index++) {
          final Answer response = await _invite(
            api,
            teamId,
            userId: 'membre-$index',
          );
          expect(response.statusCode, 201);
        }

        final Answer refused = await _invite(api, teamId, userId: 'membre-6');

        expect(refused.statusCode, 409);
        expect(refused.error['code'], 'conflict');
        expect(refused.error['message'], contains('5'));
        expect((refused.error['details'] as Map<String, dynamic>)['limit'], 5);
      },
    );

    test(
      'une formule inférieure refuse l\'invitation au-delà du siège',
      () async {
        final TeamApi api = TeamApi.start();
        final String teamId = await _createTeam(api);

        final Answer first = await _invite(api, teamId, userId: 'membre-1');
        expect(first.statusCode, 201);

        final Answer refused = await _invite(api, teamId, userId: 'membre-2');

        expect(refused.statusCode, 402);
        expect(refused.error['code'], 'plan_limit_reached');
        expect(refused.error['message'], contains('Studio'));
        expect(
          (refused.error['details'] as Map<String, dynamic>)['required_plan'],
          'Studio',
        );
      },
    );
  });

  group('validations', () {
    late TeamApi api;

    setUp(() {
      api = TeamApi.start(planLookup: _studioPlan);
    });

    test('refuse un nom d\'équipe vide', () async {
      final Answer response = await api.send(
        'POST',
        '/v1/teams',
        body: <String, Object?>{'name': '   '},
      );

      expect(response.statusCode, 400);
      expect(response.error['code'], 'validation_failed');
    });

    test('refuse un rôle inconnu', () async {
      final String teamId = await _createTeam(api);

      final Answer response = await api.send(
        'POST',
        '/v1/teams/$teamId/invitations',
        body: <String, Object?>{'user_id': 'membre-1', 'role': 'directeur'},
      );

      expect(response.statusCode, 400);
      expect(response.error['code'], 'validation_failed');
    });

    test('refuse d\'attribuer le rôle de propriétaire', () async {
      final String teamId = await _createTeam(api);

      final Answer response = await _invite(
        api,
        teamId,
        userId: 'membre-1',
        role: 'owner',
      );

      expect(response.statusCode, 400);
      expect(response.error['code'], 'validation_failed');
      expect(response.error['message'], contains('propriétaire'));
    });

    test('refuse d\'inviter un compte déjà membre', () async {
      final String teamId = await _createTeam(api);
      await _invite(api, teamId, userId: 'membre-1');

      final Answer response = await _invite(api, teamId, userId: 'membre-1');

      expect(response.statusCode, 409);
      expect(response.error['code'], 'conflict');
    });
  });

  group('base SQLite', () {
    late SqliteDatabase database;
    late TeamApi api;

    setUp(() async {
      database = await SqliteDatabase.openInMemory();
      await _applyTeamMigration(database);
      api = TeamApi.start(
        database: SqliteTeamDatabase(database, planLookup: _studioPlan),
      );
    });

    tearDown(() async {
      await database.close();
    });

    test('applique la migration et gère les invitations', () async {
      final String teamId = await _createTeam(api);

      final Answer invited = await _invite(api, teamId, userId: 'membre-1');
      expect(invited.statusCode, 201);

      final Answer members = await api.send('GET', '/v1/teams/$teamId/members');
      expect(members.items, hasLength(2));
      expect((members.items.first as Map<String, dynamic>)['role'], 'owner');
    });

    test('refuse la sixième invitation', () async {
      final String teamId = await _createTeam(api);
      for (var index = 1; index <= 5; index++) {
        final Answer response = await _invite(
          api,
          teamId,
          userId: 'membre-$index',
        );
        expect(response.statusCode, 201);
      }

      final Answer refused = await _invite(api, teamId, userId: 'membre-6');

      expect(refused.statusCode, 409);
      expect(refused.error['message'], contains('5'));
    });
  });
}
