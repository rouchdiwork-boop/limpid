import 'package:limpid_api/src/db/team_invitation_record.dart';
import 'package:limpid_api/src/db/team_invitation_store.dart';
import 'package:limpid_api/src/db/team_record.dart';
import 'package:test/test.dart';

/// Les invitations sous test.
final class TeamInvitationFixture {
  /// Crée un cas.
  const TeamInvitationFixture({
    required this.invitations,
    required this.dispose,
  });

  /// Le magasin des invitations.
  final TeamInvitationStore invitations;

  /// Libère les ressources du cas.
  final Future<void> Function() dispose;
}

/// L'instant des enregistrements du contrat.
final DateTime _moment = DateTime.utc(2026, 11, 1);

/// L'échéance des invitations du contrat.
final DateTime _expiry = DateTime.utc(2026, 11, 8);

/// L'échéance d'une invitation qui a expiré.
///
/// La date est dans le passé : une invitation qui a expiré ne se relance
/// pas, quelle que soit l'heure à laquelle on la regarde.
final DateTime _expired = DateTime.utc(2020, 1, 1);

/// Exécute le contrat du port [TeamInvitationStore].
///
/// Les mêmes scénarios tournent contre le magasin en mémoire et contre le
/// magasin SQLite : l'égalité des deux exécutions est la preuve que la base
/// de développement se comporte comme l'implémentation de référence.
void runTeamInvitationStoreContract({
  required String name,
  required Future<TeamInvitationFixture> Function() build,
}) {
  group('contrat des invitations — $name', () {
    late TeamInvitationFixture fixture;

    setUp(() async {
      fixture = await build();
    });

    tearDown(() async {
      await fixture.dispose();
    });

    test('enregistre une invitation et la relit', () async {
      await fixture.invitations.insert(_invitation('invitation-1'));

      final TeamInvitationRecord? stored = await fixture.invitations.findById(
        'invitation-1',
      );

      expect(stored, isNotNull);
      expect(stored!.teamId, 'team-1');
      expect(stored.email, 'invite@exemple.fr');
      expect(stored.role, TeamRole.coAuthor);
      expect(stored.tokenHash, 'hash-invitation-1');
      expect(stored.status, TeamInvitationStatus.pending);
      expect(stored.invitedBy, 'owner-1');
      expect(stored.createdAt, _moment);
      expect(stored.expiresAt, _expiry);
      expect(stored.acceptedAt, isNull);
    });

    test('ne rend pas une invitation inconnue', () async {
      expect(await fixture.invitations.findById('invitation-absent'), isNull);
    });

    test(
      'liste les invitations de l\'équipe, les plus récentes d\'abord',
      () async {
        await fixture.invitations.insert(_invitation('invitation-1'));
        await fixture.invitations.insert(
          _invitation(
            'invitation-2',
            createdAt: _moment.add(const Duration(hours: 1)),
          ),
        );
        await fixture.invitations.insert(
          _invitation('invitation-3', teamId: 'team-2'),
        );

        final List<TeamInvitationRecord> listed = await fixture.invitations
            .listByTeam(teamId: 'team-1');

        expect(listed, hasLength(2));
        expect(listed.first.id, 'invitation-2');
        expect(listed.last.id, 'invitation-1');
      },
    );

    test('trouve l\'invitation en attente de l\'adresse', () async {
      await fixture.invitations.insert(_invitation('invitation-1'));

      final TeamInvitationRecord? found = await fixture.invitations
          .findPendingByEmail(teamId: 'team-1', email: 'invite@exemple.fr');

      expect(found, isNotNull);
      expect(found!.id, 'invitation-1');
    });

    test('ne trouve pas une invitation expirée', () async {
      await fixture.invitations.insert(
        _invitation('invitation-1', expiresAt: _expired),
      );

      final TeamInvitationRecord? found = await fixture.invitations
          .findPendingByEmail(teamId: 'team-1', email: 'invite@exemple.fr');

      expect(found, isNull);
    });

    test('accepte une invitation une seule fois', () async {
      await fixture.invitations.insert(_invitation('invitation-1'));

      final bool accepted = await fixture.invitations.markAccepted(
        id: 'invitation-1',
        userId: 'member-2',
        acceptedAt: _moment.add(const Duration(hours: 2)),
      );

      expect(accepted, isTrue);

      final TeamInvitationRecord? stored = await fixture.invitations.findById(
        'invitation-1',
      );
      expect(stored!.status, TeamInvitationStatus.accepted);
      expect(stored.acceptedBy, 'member-2');
      expect(stored.acceptedAt, _moment.add(const Duration(hours: 2)));

      final bool again = await fixture.invitations.markAccepted(
        id: 'invitation-1',
        userId: 'member-3',
        acceptedAt: _moment.add(const Duration(hours: 3)),
      );
      expect(again, isFalse);
    });

    test('n\'accepte pas une invitation expirée', () async {
      await fixture.invitations.insert(
        _invitation('invitation-1', expiresAt: _expired),
      );

      final bool accepted = await fixture.invitations.markAccepted(
        id: 'invitation-1',
        userId: 'member-2',
        acceptedAt: _moment,
      );

      expect(accepted, isFalse);
    });

    test('révoque une invitation en attente', () async {
      await fixture.invitations.insert(_invitation('invitation-1'));

      final TeamInvitationRecord? revoked = await fixture.invitations.revoke(
        id: 'invitation-1',
        teamId: 'team-1',
      );

      expect(revoked, isNotNull);
      expect(revoked!.status, TeamInvitationStatus.revoked);
    });

    test('ne révoque pas une invitation déjà acceptée', () async {
      await fixture.invitations.insert(_invitation('invitation-1'));
      await fixture.invitations.markAccepted(
        id: 'invitation-1',
        userId: 'member-2',
        acceptedAt: _moment,
      );

      final TeamInvitationRecord? revoked = await fixture.invitations.revoke(
        id: 'invitation-1',
        teamId: 'team-1',
      );

      expect(revoked, isNotNull);
      expect(revoked!.status, TeamInvitationStatus.accepted);
    });

    test('ne révoque pas une invitation inconnue', () async {
      final TeamInvitationRecord? revoked = await fixture.invitations.revoke(
        id: 'invitation-absent',
        teamId: 'team-1',
      );

      expect(revoked, isNull);
    });
  });
}

/// L'invitation du contrat.
TeamInvitationRecord _invitation(
  String id, {
  String teamId = 'team-1',
  DateTime? createdAt,
  DateTime? expiresAt,
}) {
  return TeamInvitationRecord(
    id: id,
    teamId: teamId,
    email: 'invite@exemple.fr',
    role: TeamRole.coAuthor,
    tokenHash: 'hash-$id',
    status: TeamInvitationStatus.pending,
    invitedBy: 'owner-1',
    createdAt: createdAt ?? _moment,
    expiresAt: expiresAt ?? _expiry,
  );
}
