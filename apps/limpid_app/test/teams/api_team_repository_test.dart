import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:limpid_app/src/data/api_client.dart';
import 'package:limpid_app/src/data/api_team_repository.dart';
import 'package:limpid_app/src/domain/errors.dart';
import 'package:limpid_app/src/domain/team_repository.dart';

void main() {
  group('ApiTeamRepository', () {
    test('lit les équipes du compte', () async {
      final ApiTeamRepository repository = _repositoryOf((
        http.Request request,
      ) async {
        expect(request.method, 'GET');
        expect(request.url.path, '/v1/teams');
        return _ok(<Object?>[
          <String, Object?>{
            'id': 'team-1',
            'name': 'La Brigade',
            'owner_id': 'owner-1',
            'created_at': '2026-11-01T00:00:00.000Z',
            'updated_at': '2026-11-02T00:00:00.000Z',
          },
        ]);
      });

      final List<Team> teams = await repository.listTeams();

      expect(teams, hasLength(1));
      expect(teams.first.id, 'team-1');
      expect(teams.first.name, 'La Brigade');
      expect(teams.first.ownerId, 'owner-1');
      expect(teams.first.createdAt, DateTime.utc(2026, 11, 1));
    });

    test('crée une équipe', () async {
      Map<String, Object?>? body;
      final ApiTeamRepository repository = _repositoryOf((
        http.Request request,
      ) async {
        expect(request.method, 'POST');
        expect(request.url.path, '/v1/teams');
        final Object? decoded = jsonDecode(request.body);
        body = decoded is Map<String, Object?> ? decoded : null;
        return _ok(<String, Object?>{
          'id': 'team-2',
          'name': 'La Brigade',
          'owner_id': 'owner-1',
          'created_at': '2026-11-01T00:00:00.000Z',
          'updated_at': '2026-11-01T00:00:00.000Z',
        }, status: 201);
      });

      final Team team = await repository.createTeam(name: 'La Brigade');

      expect(body?['name'], 'La Brigade');
      expect(team.id, 'team-2');
      expect(team.ownerId, 'owner-1');
    });

    test('lit les membres et leur rôle', () async {
      final ApiTeamRepository repository = _repositoryOf((
        http.Request request,
      ) async {
        expect(request.method, 'GET');
        expect(request.url.path, '/v1/teams/team-1/members');
        return _ok(<Object?>[
          <String, Object?>{
            'team_id': 'team-1',
            'user_id': 'owner-1',
            'role': 'owner',
            'created_at': '2026-11-01T00:00:00.000Z',
          },
          <String, Object?>{
            'team_id': 'team-1',
            'user_id': 'member-2',
            'role': 'coAuthor',
            'created_at': '2026-11-01T00:00:00.000Z',
          },
        ]);
      });

      final List<TeamMember> members = await repository.listMembers(
        teamId: 'team-1',
      );

      expect(members, hasLength(2));
      expect(members.first.role, TeamRole.owner);
      expect(members.first.takesSeat, isFalse);
      expect(members.last.role, TeamRole.coAuthor);
      expect(members.last.userId, 'member-2');
    });

    test('invite un compte avec le rôle du serveur', () async {
      Map<String, Object?>? body;
      final ApiTeamRepository repository = _repositoryOf((
        http.Request request,
      ) async {
        expect(request.method, 'POST');
        expect(request.url.path, '/v1/teams/team-1/invitations');
        final Object? decoded = jsonDecode(request.body);
        body = decoded is Map<String, Object?> ? decoded : null;
        return _ok(<String, Object?>{
          'id': 'invitation-1',
          'team_id': 'team-1',
          'user_id': 'member-2',
          'role': 'betaReader',
          'invited_by': 'owner-1',
          'created_at': '2026-11-01T00:00:00.000Z',
        }, status: 201);
      });

      final TeamInvitation invitation = await repository.invite(
        teamId: 'team-1',
        userId: 'member-2',
        role: TeamRole.betaReader,
      );

      expect(body?['user_id'], 'member-2');
      expect(body?['role'], 'betaReader');
      expect(invitation.role, TeamRole.betaReader);
      expect(invitation.invitedBy, 'owner-1');
    });

    test(
      'invite une adresse et rend le lien quand le serveur le rend',
      () async {
        Map<String, Object?>? body;
        final ApiTeamRepository repository = _repositoryOf((
          http.Request request,
        ) async {
          expect(request.method, 'POST');
          expect(request.url.path, '/v1/teams/team-1/invitations');
          final Object? decoded = jsonDecode(request.body);
          body = decoded is Map<String, Object?> ? decoded : null;
          return _ok(<String, Object?>{
            'id': 'invitation-1',
            'team_id': 'team-1',
            'email': 'invite@exemple.fr',
            'role': 'betaReader',
            'status': 'pending',
            'invited_by': 'owner-1',
            'created_at': '2026-11-01T00:00:00.000Z',
            'expires_at': '2026-11-08T00:00:00.000Z',
            'invitation_link':
                'https://api.test/v1/team-invitations/lt.1.s/accept',
          }, status: 201);
        });

        final CreatedTeamInvitation created = await repository.inviteByEmail(
          teamId: 'team-1',
          email: 'invite@exemple.fr',
          role: TeamRole.betaReader,
        );

        expect(body?['email'], 'invite@exemple.fr');
        expect(body?['role'], 'betaReader');
        expect(created.invitation.email, 'invite@exemple.fr');
        expect(created.invitation.status, TeamInvitationStatus.pending);
        expect(created.invitation.expiresAt, DateTime.utc(2026, 11, 8));
        expect(created.link, contains('/v1/team-invitations/'));
      },
    );

    test('lit les invitations et leur état', () async {
      final ApiTeamRepository repository = _repositoryOf((
        http.Request request,
      ) async {
        expect(request.method, 'GET');
        expect(request.url.path, '/v1/teams/team-1/invitations');
        return _ok(<Object?>[
          <String, Object?>{
            'id': 'invitation-1',
            'team_id': 'team-1',
            'email': 'invite@exemple.fr',
            'role': 'coAuthor',
            'status': 'expired',
            'invited_by': 'owner-1',
            'created_at': '2026-11-01T00:00:00.000Z',
            'expires_at': '2026-11-08T00:00:00.000Z',
          },
        ]);
      });

      final List<TeamEmailInvitation> invitations = await repository
          .listInvitations(teamId: 'team-1');

      expect(invitations, hasLength(1));
      expect(invitations.first.email, 'invite@exemple.fr');
      expect(invitations.first.status, TeamInvitationStatus.expired);
      expect(invitations.first.isExpired, isTrue);
      expect(invitations.first.isPending, isFalse);
    });

    test('révoque une invitation', () async {
      final ApiTeamRepository repository = _repositoryOf((
        http.Request request,
      ) async {
        expect(request.method, 'DELETE');
        expect(request.url.path, '/v1/teams/team-1/invitations/invitation-1');
        return _ok(<String, Object?>{
          'id': 'invitation-1',
          'team_id': 'team-1',
          'email': 'invite@exemple.fr',
          'role': 'coAuthor',
          'status': 'revoked',
          'invited_by': 'owner-1',
          'created_at': '2026-11-01T00:00:00.000Z',
          'expires_at': '2026-11-08T00:00:00.000Z',
        });
      });

      final TeamEmailInvitation revoked = await repository.revokeInvitation(
        teamId: 'team-1',
        invitationId: 'invitation-1',
      );

      expect(revoked.status, TeamInvitationStatus.revoked);
      expect(revoked.isRevoked, isTrue);
    });

    test('accepte une invitation par son jeton', () async {
      final ApiTeamRepository repository = _repositoryOf((
        http.Request request,
      ) async {
        expect(request.method, 'POST');
        expect(request.url.path, '/v1/team-invitations/lt.1.secret/accept');
        return _ok(<String, Object?>{
          'id': 'invitation-1',
          'team_id': 'team-1',
          'email': 'invite@exemple.fr',
          'role': 'coAuthor',
          'status': 'accepted',
          'invited_by': 'owner-1',
          'created_at': '2026-11-01T00:00:00.000Z',
          'expires_at': '2026-11-08T00:00:00.000Z',
          'accepted_at': '2026-11-02T00:00:00.000Z',
          'accepted_by': 'member-2',
        });
      });

      final TeamEmailInvitation accepted = await repository.acceptInvitation(
        token: 'lt.1.secret',
      );

      expect(accepted.status, TeamInvitationStatus.accepted);
      expect(accepted.isAccepted, isTrue);
      expect(accepted.acceptedBy, 'member-2');
    });

    test('change le rôle d’un membre', () async {
      Map<String, Object?>? body;
      final ApiTeamRepository repository = _repositoryOf((
        http.Request request,
      ) async {
        expect(request.method, 'PATCH');
        expect(request.url.path, '/v1/teams/team-1/members/member-2');
        final Object? decoded = jsonDecode(request.body);
        body = decoded is Map<String, Object?> ? decoded : null;
        return _ok(<String, Object?>{
          'team_id': 'team-1',
          'user_id': 'member-2',
          'role': 'reader',
          'created_at': '2026-11-01T00:00:00.000Z',
        });
      });

      final TeamMember member = await repository.changeRole(
        teamId: 'team-1',
        userId: 'member-2',
        role: TeamRole.reader,
      );

      expect(body?['role'], 'reader');
      expect(member.role, TeamRole.reader);
    });

    test('retire un membre', () async {
      final ApiTeamRepository repository = _repositoryOf((
        http.Request request,
      ) async {
        expect(request.method, 'DELETE');
        expect(request.url.path, '/v1/teams/team-1/members/member-2');
        return _ok(<String, Object?>{
          'team_id': 'team-1',
          'user_id': 'member-2',
          'removed': true,
        });
      });

      await repository.removeMember(teamId: 'team-1', userId: 'member-2');
    });

    test('supprime une équipe', () async {
      final ApiTeamRepository repository = _repositoryOf((
        http.Request request,
      ) async {
        expect(request.method, 'DELETE');
        expect(request.url.path, '/v1/teams/team-1');
        return _ok(<String, Object?>{'id': 'team-1', 'deleted': true});
      });

      await repository.deleteTeam(teamId: 'team-1');
    });

    test('remonte une erreur typée quand le serveur refuse', () async {
      final ApiTeamRepository repository = _repositoryOf(
        (http.Request request) async => http.Response(
          jsonEncode(<String, Object?>{
            'error': <String, Object?>{
              'code': 'not_found',
              'message': "Cette ressource n'existe pas.",
            },
          }),
          404,
          headers: <String, String>{'content-type': 'application/json'},
        ),
      );

      await expectLater(
        repository.listMembers(teamId: 'team-1'),
        throwsA(isA<ApiNotFoundException>()),
      );
    });

    test('refuse une réponse qui n’est pas une liste', () async {
      final ApiTeamRepository repository = _repositoryOf(
        (http.Request request) async => _ok(<String, Object?>{}),
      );

      await expectLater(
        repository.listTeams(),
        throwsA(isA<ApiMalformedResponseException>()),
      );
    });
  });
}

/// Builds a repository talking to a fake server.
ApiTeamRepository _repositoryOf(
  Future<http.Response> Function(http.Request request) handler,
) => ApiTeamRepository(
  client: ApiClient(
    baseUrl: Uri.parse('https://api.test'),
    client: MockClient(handler),
  ),
);

/// Builds a successful answer carrying the envelope of the API.
http.Response _ok(Object? data, {int status = 200}) => http.Response(
  jsonEncode(<String, Object?>{'data': data}),
  status,
  headers: <String, String>{'content-type': 'application/json'},
);
