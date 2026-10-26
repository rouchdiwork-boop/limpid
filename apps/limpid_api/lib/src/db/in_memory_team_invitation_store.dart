import 'team_invitation_record.dart';
import 'team_invitation_store.dart';

/// L'implémentation en mémoire du port [TeamInvitationStore].
///
/// Le magasin garde les mêmes invariants que les implémentations SQL : le
/// jeton n'est jamais stocké en clair, la liste est triée comme la liste
/// SQL, et l'acceptation est conditionnelle — une invitation déjà utilisée
/// ne s'accepte pas une seconde fois.
final class InMemoryTeamInvitationStore implements TeamInvitationStore {
  /// Crée un magasin vide.
  InMemoryTeamInvitationStore();

  /// Les invitations, par identifiant.
  final Map<String, TeamInvitationRecord> _invitations =
      <String, TeamInvitationRecord>{};

  @override
  Future<TeamInvitationRecord?> findById(String id) async => _invitations[id];

  @override
  Future<List<TeamInvitationRecord>> listByTeam({
    required String teamId,
  }) async {
    final List<TeamInvitationRecord> owned = _invitations.values
        .where(
          (TeamInvitationRecord invitation) =>
              invitation.teamId == teamId && invitation.email.isNotEmpty,
        )
        .toList(growable: false);
    final List<TeamInvitationRecord> sorted =
        List<TeamInvitationRecord>.of(owned)
          ..sort((TeamInvitationRecord left, TeamInvitationRecord right) {
            final int byDate = right.createdAt.compareTo(left.createdAt);
            if (byDate != 0) return byDate;
            return left.id.compareTo(right.id);
          });
    return List<TeamInvitationRecord>.unmodifiable(sorted);
  }

  @override
  Future<TeamInvitationRecord?> findPendingByEmail({
    required String teamId,
    required String email,
  }) async {
    for (final TeamInvitationRecord invitation in _invitations.values) {
      if (invitation.teamId != teamId) continue;
      if (invitation.email != email) continue;
      if (!invitation.isPendingAt(DateTime.now().toUtc())) continue;
      return invitation;
    }
    return null;
  }

  @override
  Future<void> insert(TeamInvitationRecord record) async {
    _invitations[record.id] = record;
  }

  @override
  Future<bool> markAccepted({
    required String id,
    required String userId,
    required DateTime acceptedAt,
  }) async {
    final TeamInvitationRecord? existing = _invitations[id];
    if (existing == null) return false;
    if (existing.status != TeamInvitationStatus.pending) return false;
    if (existing.isExpiredAt(acceptedAt)) return false;
    _invitations[id] = existing.copyWith(
      status: TeamInvitationStatus.accepted,
      acceptedAt: acceptedAt,
      acceptedBy: userId,
    );
    return true;
  }

  @override
  Future<TeamInvitationRecord?> revoke({
    required String id,
    required String teamId,
  }) async {
    final TeamInvitationRecord? existing = _invitations[id];
    if (existing == null || existing.teamId != teamId) return null;
    if (existing.status != TeamInvitationStatus.pending) return existing;
    final TeamInvitationRecord revoked = existing.copyWith(
      status: TeamInvitationStatus.revoked,
    );
    _invitations[id] = revoked;
    return revoked;
  }
}
