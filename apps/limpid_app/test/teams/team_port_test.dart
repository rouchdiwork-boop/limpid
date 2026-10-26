import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:limpid_app/src/domain/providers.dart';
import 'package:limpid_app/src/domain/team_repository.dart';

import 'fakes.dart';

void main() {
  group('UnavailableTeamRepository', () {
    const UnavailableTeamRepository repository = UnavailableTeamRepository();

    test('refuse de lister les équipes', () async {
      await expectLater(
        repository.listTeams(),
        throwsA(isA<ServiceUnavailableException>()),
      );
    });

    test('refuse de créer une équipe', () async {
      await expectLater(
        repository.createTeam(name: 'La Brigade'),
        throwsA(isA<ServiceUnavailableException>()),
      );
    });

    test('refuse de lister les membres', () async {
      await expectLater(
        repository.listMembers(teamId: 'team-1'),
        throwsA(isA<ServiceUnavailableException>()),
      );
    });

    test('refuse d’inviter un compte', () async {
      await expectLater(
        repository.invite(
          teamId: 'team-1',
          userId: 'member-2',
          role: TeamRole.coAuthor,
        ),
        throwsA(isA<ServiceUnavailableException>()),
      );
    });

    test('refuse d’inviter une adresse', () async {
      await expectLater(
        repository.inviteByEmail(
          teamId: 'team-1',
          email: 'invite@exemple.fr',
          role: TeamRole.coAuthor,
        ),
        throwsA(isA<ServiceUnavailableException>()),
      );
    });

    test('refuse de lister les invitations', () async {
      await expectLater(
        repository.listInvitations(teamId: 'team-1'),
        throwsA(isA<ServiceUnavailableException>()),
      );
    });

    test('refuse de révoquer une invitation', () async {
      await expectLater(
        repository.revokeInvitation(
          teamId: 'team-1',
          invitationId: 'invitation-1',
        ),
        throwsA(isA<ServiceUnavailableException>()),
      );
    });

    test('refuse d’accepter une invitation', () async {
      await expectLater(
        repository.acceptInvitation(token: 'lt.1.secret'),
        throwsA(isA<ServiceUnavailableException>()),
      );
    });

    test('refuse de changer un rôle', () async {
      await expectLater(
        repository.changeRole(
          teamId: 'team-1',
          userId: 'member-2',
          role: TeamRole.reader,
        ),
        throwsA(isA<ServiceUnavailableException>()),
      );
    });

    test('refuse de retirer un membre', () async {
      await expectLater(
        repository.removeMember(teamId: 'team-1', userId: 'member-2'),
        throwsA(isA<ServiceUnavailableException>()),
      );
    });

    test('refuse de supprimer une équipe', () async {
      await expectLater(
        repository.deleteTeam(teamId: 'team-1'),
        throwsA(isA<ServiceUnavailableException>()),
      );
    });

    test('se déclare comme un service indisponible', () {
      expect(repository, isA<UnavailableService>());
    });
  });

  group('teamRepositoryProvider', () {
    test('vaut la doublure indisponible par défaut', () {
      final ProviderContainer container = ProviderContainer();
      addTearDown(container.dispose);

      expect(
        container.read(teamRepositoryProvider),
        isA<UnavailableTeamRepository>(),
      );
    });
  });

  group('TeamRole', () {
    test('lit les rôles que le serveur publie', () {
      expect(TeamRole.parse('owner'), TeamRole.owner);
      expect(TeamRole.parse('coAuthor'), TeamRole.coAuthor);
      expect(TeamRole.parse('betaReader'), TeamRole.betaReader);
      expect(TeamRole.parse('reader'), TeamRole.reader);
    });

    test('ne connaît pas un rôle qu’il ne nomme pas', () {
      expect(TeamRole.parse('externalGuest'), isNull);
    });

    test('n’attribue que les rôles que l’interface nomme', () {
      expect(assignableTeamRoles, <TeamRole>[
        TeamRole.coAuthor,
        TeamRole.betaReader,
        TeamRole.reader,
      ]);
      expect(assignableTeamRoles, isNot(contains(TeamRole.owner)));
    });
  });

  group('TeamMember', () {
    test('le propriétaire ne prend pas de siège', () {
      expect(fakeOwner.takesSeat, isFalse);
      expect(fakeCoAuthor.takesSeat, isTrue);
    });
  });
}
