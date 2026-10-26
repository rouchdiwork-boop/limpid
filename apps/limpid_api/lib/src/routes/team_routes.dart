import 'dart:io';

import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import '../auth/auth_middleware.dart';
import '../config/app_config.dart';
import '../db/team_database.dart';
import '../db/team_record.dart';
import '../http/api_response.dart';
import '../http/json_body.dart';
import '../services/team_service.dart';

/// Le nombre maximal de caractères du nom d'une équipe.
const int maxTeamNameLength = 120;

/// Le nombre maximal de caractères de l'identifiant d'un compte invité.
const int maxAccountIdLength = 200;

/// Enregistre les routes des équipes.
///
/// Les équipes portent les rôles de D-16 : une équipe se crée, on y invite
/// des comptes, on change leur rôle et on les retire. La lecture de la
/// formule du compte est injectée par la composition, dans la base : le
/// service ne dépend pas du fichier des formules.
///
/// Le propriétaire est le seul à administrer l'équipe. Un appelant qui n'en
/// est pas membre reçoit un 404, jamais un 403 : l'existence d'une équipe
/// ne se divulgue pas.
void registerTeamRoutes(
  Router router,
  TeamDatabase database,
  AppConfig config,
) {
  final TeamService service = TeamService(database);

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
    return ApiResponse.ok(invitation.toJson(), status: HttpStatus.created);
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
