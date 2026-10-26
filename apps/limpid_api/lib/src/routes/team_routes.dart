import 'dart:io';

import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import '../auth/auth_middleware.dart';
import '../config/app_config.dart';
import '../db/audit_entry.dart';
import '../db/audit_log.dart';
import '../db/team_database.dart';
import '../db/team_invitation_record.dart';
import '../db/team_invitation_store.dart';
import '../db/team_record.dart';
import '../errors/app_exception.dart';
import '../http/api_response.dart';
import '../http/json_body.dart';
import '../middleware/rate_limiter.dart';
import '../services/mailer.dart';
import '../services/team_service.dart';
import '../services/webhook_dispatcher.dart';

/// Le nombre maximal de caractères du nom d'une équipe.
const int maxTeamNameLength = 120;

/// Le nombre maximal de caractères de l'identifiant d'un compte invité.
const int maxAccountIdLength = 200;

/// Le nombre maximal de caractères d'une adresse électronique invitée.
const int maxInvitedEmailLength = 254;

/// Le nombre d'invitations qu'un compte peut burstir.
///
/// Une invitation déclenche un courriel et tient un siège : la route ne
/// laisse pas un compte la remplir sans fin.
const int teamInvitationRateLimitCapacity = 10;

/// Le nombre d'invitations qu'un compte regagne par seconde.
const double teamInvitationRateLimitRefillPerSecond = 0.5;

/// Enregistre les routes des équipes.
///
/// Les équipes portent les rôles de D-16 : une équipe se crée, on y invite
/// des comptes, on change leur rôle et on les retire. La lecture de la
/// formule du compte est injectée par la composition, dans la base : le
/// service ne dépend pas du fichier des formules.
///
/// Le propriétaire est le seul à administrer l'équipe. Un appelant qui n'en
/// est pas membre reçoit un 404, jamais un 403 : l'existence d'une équipe
/// ne divulgue pas.
///
/// L'invitation par courriel est un chemin **à côté** de l'invitation
/// d'un compte existant : la route `POST /v1/teams/<teamId>/invitations`
/// lit le corps et reconnaît le chemin. Le chemin par courriel attend une
/// réponse : le membre n'entre dans l'équipe qu'à l'acceptation, et
/// l'invitation expire.
///
/// Le dispatcher est facultatif : sans lui, l'invitation n'est pas annoncée
/// aux webhooks, mais elle est toujours envoyée et toujours tracée.
///
/// [clock] et [invitationRateLimitCapacity] existent pour que la suite de
/// tests puisse faire passer le temps et poser une limite étroite sans
/// attendre.
void registerTeamRoutes(
  Router router,
  TeamDatabase database,
  AppConfig config, {
  AuditLog? audit,
  WebhookDispatcher? dispatcher,
  TeamInvitationStore? invitations,
  Mailer? mailer,
  String? publicBaseUrl,
  DateTime Function()? clock,
  int invitationRateLimitCapacity = teamInvitationRateLimitCapacity,
}) {
  final TeamService service = TeamService(
    database,
    dispatcher: dispatcher,
    invitations: invitations,
    mailer: mailer ?? LogMailer(),
    invitationBaseUrl: publicBaseUrl ?? defaultPublicBaseUrl,
    clock: clock,
  );
  final TokenBucketRateLimiter limiter = TokenBucketRateLimiter(
    capacity: invitationRateLimitCapacity,
    refillPerSecond: teamInvitationRateLimitRefillPerSecond,
  );
  final Middleware limit = rateLimitMiddleware(
    limiter: limiter,
    scope: 'team_invitation',
    applies: (Request request) =>
        isTeamInvitationPath(request.requestedUri.path),
    keyOf: (Request request) => authOf(request)?.userId ?? clientIpOf(request),
  );

  router.get('/v1/teams', (Request request) async {
    final AuthContext auth = requireAuthContext(request);
    final List<TeamRecord> teams = await service.listTeams(auth.userId);
    return ApiResponse.ok(
      teams.map((TeamRecord team) => team.toJson()).toList(growable: false),
    );
  });

  router.post('/v1/teams', (Request request) async {
    final AuthContext auth = requireAuthContext(request);
    final JsonBody body = await JsonBody.fromRequest(
      request,
      maxBytes: config.maxBodyBytes,
    );
    final String name = body.requireString(
      'name',
      maxLength: maxTeamNameLength,
    );

    final TeamRecord team = await service.createTeam(
      ownerId: auth.userId,
      name: name,
    );
    return ApiResponse.ok(team.toJson(), status: HttpStatus.created);
  });

  router.get('/v1/teams/<teamId>/members', (
    Request request,
    String teamId,
  ) async {
    final AuthContext auth = requireAuthContext(request);
    final List<TeamMember> members = await service.listMembers(
      teamId: teamId,
      callerId: auth.userId,
    );
    return ApiResponse.ok(
      members
          .map((TeamMember member) => member.toJson())
          .toList(growable: false),
    );
  });

  router.post('/v1/teams/<teamId>/invitations', (
    Request request,
    String teamId,
  ) async {
    final AuthContext auth = requireAuthContext(request);
    final JsonBody body = await JsonBody.fromRequest(
      request,
      maxBytes: config.maxBodyBytes,
    );

    // Le corps dit le chemin : une adresse attend une réponse, un
    // identifiant de compte invite immédiatement.
    if (body.has('email') && body.has('user_id')) {
      throw const ValidationException(
        field: 'email',
        message:
            'Une invitation porte soit une adresse, soit un identifiant de '
            'compte, jamais les deux.',
      );
    }
    if (body.has('email')) {
      return limit(
        (Request request) =>
            _createEmailInvitation(request, service, audit, auth, teamId, body),
      )(request);
    }

    final String userId = body.requireString(
      'user_id',
      maxLength: maxAccountIdLength,
    );
    final TeamRole role = body.requireEnum('role', TeamRole.values);

    final TeamInvitation invitation = await service.invite(
      teamId: teamId,
      callerId: auth.userId,
      userId: userId,
      role: role,
    );
    await _traceInvitation(request, audit, auth, teamId, role);
    return ApiResponse.ok(invitation.toJson(), status: HttpStatus.created);
  });

  router.get('/v1/teams/<teamId>/invitations', (
    Request request,
    String teamId,
  ) async {
    final AuthContext auth = requireAuthContext(request);
    final List<TeamInvitationRecord> invitations = await service
        .listInvitations(teamId: teamId, callerId: auth.userId);
    return ApiResponse.ok(
      invitations
          .map((TeamInvitationRecord invitation) => invitation.toJson())
          .toList(growable: false),
    );
  });

  router.delete('/v1/teams/<teamId>/invitations/<invitationId>', (
    Request request,
    String teamId,
    String invitationId,
  ) async {
    final AuthContext auth = requireAuthContext(request);
    final TeamInvitationRecord revoked = await service.revokeInvitation(
      teamId: teamId,
      callerId: auth.userId,
      invitationId: invitationId,
    );
    await _trace(
      request,
      audit,
      userId: auth.userId,
      action: 'team.email_invitation_revoked',
      targetType: 'team',
      targetId: teamId,
      metadata: <String, Object?>{'invitation_id': revoked.id},
    );
    return ApiResponse.ok(revoked.toJson());
  });

  router.post('/v1/team-invitations/<token>/accept', (
    Request request,
    String token,
  ) async {
    final AuthContext auth = requireAuthContext(request);
    return limit(
      (Request request) =>
          _acceptInvitation(request, service, audit, auth, token),
    )(request);
  });

  router.patch('/v1/teams/<teamId>/members/<userId>', (
    Request request,
    String teamId,
    String userId,
  ) async {
    final AuthContext auth = requireAuthContext(request);
    final JsonBody body = await JsonBody.fromRequest(
      request,
      maxBytes: config.maxBodyBytes,
    );
    final TeamRole role = body.requireEnum('role', TeamRole.values);

    final TeamMember member = await service.changeRole(
      teamId: teamId,
      callerId: auth.userId,
      userId: userId,
      role: role,
    );
    return ApiResponse.ok(member.toJson());
  });

  router.delete('/v1/teams/<teamId>/members/<userId>', (
    Request request,
    String teamId,
    String userId,
  ) async {
    final AuthContext auth = requireAuthContext(request);
    await service.removeMember(
      teamId: teamId,
      callerId: auth.userId,
      userId: userId,
    );
    return ApiResponse.ok(<String, Object?>{
      'team_id': teamId,
      'user_id': userId,
      'removed': true,
    });
  });

  router.delete('/v1/teams/<teamId>', (Request request, String teamId) async {
    final AuthContext auth = requireAuthContext(request);
    await service.deleteTeam(teamId: teamId, callerId: auth.userId);
    return ApiResponse.ok(<String, Object?>{'id': teamId, 'deleted': true});
  });
}

/// Indique si [path] est une route d'invitation d'équipe.
///
/// La reconnaissance est précise : seules la création, la liste et la
/// révocation des invitations, et l'acceptation d'un jeton, sont concernées.
bool isTeamInvitationPath(String path) {
  if (path.startsWith('/v1/team-invitations/')) return true;
  if (!path.startsWith('/v1/teams/')) return false;
  return path.endsWith('/invitations') || path.contains('/invitations/');
}

/// Crée l'invitation par courriel et rend la réponse.
///
/// Le lien n'est rendu que lorsqu'aucun fournisseur de courriel n'est
/// configuré : il est alors montré une seule fois, comme le jeton d'un
/// partage. Quand le fournisseur est configuré, le lien part par courriel
/// et n'est plus rendu.
Future<Response> _createEmailInvitation(
  Request request,
  TeamService service,
  AuditLog? journal,
  AuthContext auth,
  String teamId,
  JsonBody body,
) async {
  final String email = body.requireString(
    'email',
    maxLength: maxInvitedEmailLength,
  );
  final TeamRole role = body.requireEnum('role', TeamRole.values);
  final int? hours = body.has('expires_in_hours')
      ? body.requireInt('expires_in_hours')
      : null;

  final CreatedTeamInvitation created = await service.inviteByEmail(
    teamId: teamId,
    callerId: auth.userId,
    email: email,
    role: role,
    lifetimeHours: hours,
  );

  await _trace(
    request,
    journal,
    userId: auth.userId,
    action: 'team.email_invitation_sent',
    targetType: 'team',
    targetId: teamId,
    metadata: <String, Object?>{
      'invitation_id': created.record.id,
      'role': created.record.role.name,
      'expires_at': created.record.expiresAt.toUtc().toIso8601String(),
    },
  );

  final Map<String, Object?> payload = created.record.toJson();
  if (!service.isMailConfigured) {
    // Le lien ne sort qu'ici : il n'est jamais rendu une seconde fois.
    payload['invitation_link'] = created.link;
  }
  return ApiResponse.ok(payload, status: HttpStatus.created);
}

/// Accepte l'invitation que porte le jeton [token].
///
/// Le compte est authentifié par le middleware : il ne peut accepter que
/// l'invitation qui porte son adresse. Un jeton inconnu, expiré, révoqué ou
/// déjà accepté répond le même 404 : les quatre cas sont indiscernables.
Future<Response> _acceptInvitation(
  Request request,
  TeamService service,
  AuditLog? journal,
  AuthContext auth,
  String token,
) async {
  final TeamInvitationRecord accepted = await service.acceptInvitation(
    token: token,
    callerId: auth.userId,
    callerEmail: auth.email,
  );
  await _trace(
    request,
    journal,
    userId: auth.userId,
    action: 'team.email_invitation_accepted',
    targetType: 'team',
    targetId: accepted.teamId,
    metadata: <String, Object?>{
      'invitation_id': accepted.id,
      'role': accepted.role.name,
    },
  );
  return ApiResponse.ok(accepted.toJson());
}

/// Trace l'invitation d'un membre dans l'équipe [teamId].
///
/// L'invitation est un acte sur le compte d'un autre : elle est tracée dans
/// le journal d'audit (D-19). Le journal est facultatif : son absence ne
/// refuse pas l'invitation, elle en prive seulement la trace.
Future<void> _traceInvitation(
  Request request,
  AuditLog? journal,
  AuthContext auth,
  String teamId,
  TeamRole role,
) async {
  final AuditLog? auditLog = journal;
  if (auditLog == null) return;
  await auditLog.record(
    AuditEntry(
      userId: auth.userId,
      action: 'team.invitation_sent',
      targetType: 'team',
      targetId: teamId,
      metadata: <String, Object?>{'role': role.name},
      ip: clientIpOf(request),
    ),
  );
}

/// Trace une action sensible dans le journal d'audit.
///
/// Aucun secret ne figure dans [metadata] : la trace dit ce qui a été fait,
/// jamais le jeton qui l'a permis, ni l'adresse de l'invité.
Future<void> _trace(
  Request request,
  AuditLog? journal, {
  required String userId,
  required String action,
  required String targetType,
  required String targetId,
  Map<String, Object?> metadata = const <String, Object?>{},
}) async {
  final AuditLog? auditLog = journal;
  if (auditLog == null) return;
  await auditLog.record(
    AuditEntry(
      userId: userId,
      action: action,
      targetType: targetType,
      targetId: targetId,
      metadata: metadata,
      ip: clientIpOf(request),
    ),
  );
}
