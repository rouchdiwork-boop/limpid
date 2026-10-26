import 'package:limpid_core/limpid_core.dart';

import '../errors/app_exception.dart';
import 'team_database.dart';
import 'team_invitation_record.dart';
import 'team_invitation_store.dart';
import 'team_record.dart';

/// La base des équipes tenue en mémoire, pour la suite de tests.
///
/// L'implémentation garde les mêmes invariants que les bases SQL : le
/// propriétaire est un membre de son équipe, le propriétaire n'occupe pas de
/// siège et l'ordre des membres est stable.
final class InMemoryTeamDatabase implements TeamDatabase {
  /// Crée une base vide.
  ///
  /// [planLookup] lit la formule du compte ; à défaut, le compte est traité
  /// comme « Gratuit ». [invitations] porte les invitations en attente : sans
  /// lui, l'acceptation d'une invitation est impossible.
  InMemoryTeamDatabase({
    PlanLookup? planLookup,
    UlidGenerator? generator,
    TeamInvitationStore? invitations,
  }) : _planLookup = planLookup ?? _freePlan,
       _ulid = generator ?? UlidGenerator(),
       // Un paramètre nommé ne peut pas commencer par « _ » : la forme que
       // le lint suggère (`this._invitations`) est interdite par le langage.
       // ignore: prefer_initializing_formals
       _invitations = invitations;

  final PlanLookup _planLookup;
  final UlidGenerator _ulid;

  /// Les invitations en attente, quand la base en connaît.
  final TeamInvitationStore? _invitations;

  final Map<String, TeamRecord> _teams = <String, TeamRecord>{};
  final Map<String, Map<String, TeamMember>> _members =
      <String, Map<String, TeamMember>>{};

  /// Renvoie toujours `null` : le compte est traité comme « Gratuit ».
  static Future<String?> _freePlan(String userId) async => null;

  @override
  PlanLookup get planLookup => _planLookup;

  @override
  Future<List<TeamRecord>> listTeams({required String userId}) async {
    final List<TeamRecord> teams =
        _teams.values
            .where(
              (TeamRecord team) =>
                  _members[team.id]?.containsKey(userId) ?? false,
            )
            .toList()
          ..sort(_compareTeams);
    return List<TeamRecord>.unmodifiable(teams);
  }

  @override
  Future<TeamMember?> findMember({
    required String teamId,
    required String userId,
  }) async {
    return _members[teamId]?[userId];
  }

  @override
  Future<TeamRecord?> findTeam({required String teamId}) async =>
      _teams[teamId];

  @override
  Future<List<TeamMember>> listMembers({required String teamId}) async {
    final List<TeamMember> members =
        (_members[teamId]?.values.toList() ?? const <TeamMember>[])
          ..sort(_compareMembers);
    return List<TeamMember>.unmodifiable(members);
  }

  @override
  Future<TeamRecord> createTeam({
    required String ownerId,
    required String name,
  }) async {
    final DateTime now = DateTime.now().toUtc();
    final TeamRecord team = TeamRecord(
      id: _ulid.generate().value,
      name: name,
      ownerId: ownerId,
      createdAt: now,
      updatedAt: now,
    );
    _teams[team.id] = team;
    _members[team.id] = <String, TeamMember>{
      ownerId: TeamMember(
        teamId: team.id,
        userId: ownerId,
        role: TeamRole.owner,
        createdAt: now,
      ),
    };
    return team;
  }

  @override
  Future<MemberAddition?> addMember({
    required String teamId,
    required String userId,
    required TeamRole role,
    required String invitedBy,
    required int maxSeats,
  }) async {
    final Map<String, TeamMember>? members = _members[teamId];
    if (members == null) {
      throw const NotFoundException();
    }
    if (members.containsKey(userId)) {
      throw const ConflictException(
        message: 'Ce compte fait déjà partie de l\'équipe.',
      );
    }
    if (_countSeats(members) >= maxSeats) return null;

    final DateTime now = DateTime.now().toUtc();
    final TeamMember member = TeamMember(
      teamId: teamId,
      userId: userId,
      role: role,
      createdAt: now,
    );
    final TeamInvitation invitation = TeamInvitation(
      id: _ulid.generate().value,
      teamId: teamId,
      userId: userId,
      role: role,
      invitedBy: invitedBy,
      createdAt: now,
    );

    _members[teamId] = <String, TeamMember>{...members, userId: member};
    return MemberAddition(member: member, invitation: invitation);
  }

  @override
  Future<TeamMember?> changeMemberRole({
    required String teamId,
    required String userId,
    required TeamRole role,
  }) async {
    final Map<String, TeamMember>? members = _members[teamId];
    final TeamMember? member = members?[userId];
    if (members == null || member == null) return null;

    final TeamMember updated = member.copyWith(role: role);
    _members[teamId] = <String, TeamMember>{...members, userId: updated};
    return updated;
  }

  @override
  Future<bool> removeMember({
    required String teamId,
    required String userId,
  }) async {
    final Map<String, TeamMember>? members = _members[teamId];
    if (members == null || !members.containsKey(userId)) return false;

    _members[teamId] = <String, TeamMember>{
      for (final MapEntry<String, TeamMember> entry in members.entries)
        if (entry.key != userId) entry.key: entry.value,
    };
    return true;
  }

  @override
  Future<bool> deleteTeam({required String teamId}) async {
    if (!_teams.containsKey(teamId)) return false;
    _teams.remove(teamId);
    _members.remove(teamId);
    return true;
  }

  @override
  Future<InvitationAcceptanceOutcome> acceptInvitation({
    required String invitationId,
    required String teamId,
    required String userId,
    required TeamRole role,
    required String invitedBy,
    required int maxSeats,
  }) async {
    final Map<String, TeamMember>? members = _members[teamId];
    if (members == null) {
      throw const NotFoundException();
    }
    if (members.containsKey(userId)) {
      throw const ConflictException(
        message: 'Ce compte fait déjà partie de l\'équipe.',
      );
    }
    // Les sièges sont vérifiés au moment de l'acceptation : la formule a pu
    // changer entre l'invitation et la réponse.
    if (_countSeats(members) >= maxSeats) {
      return InvitationAcceptanceOutcome.noSeat;
    }
    final TeamInvitationStore? store = _invitations;
    if (store == null) {
      throw StateError(
        'The in-memory team database needs an invitation store to accept '
        'an invitation.',
      );
    }
    final DateTime now = DateTime.now().toUtc();
    final bool claimed = await store.markAccepted(
      id: invitationId,
      userId: userId,
      acceptedAt: now,
    );
    if (!claimed) {
      return InvitationAcceptanceOutcome.alreadyUsed;
    }
    final TeamMember member = TeamMember(
      teamId: teamId,
      userId: userId,
      role: role,
      createdAt: now,
    );
    _members[teamId] = <String, TeamMember>{...members, userId: member};
    return InvitationAcceptanceOutcome.accepted;
  }

  /// Compte les sièges occupés : le propriétaire n'occupe pas de siège.
  static int _countSeats(Map<String, TeamMember> members) {
    return members.values
        .where((TeamMember member) => member.role != TeamRole.owner)
        .length;
  }

  static int _compareTeams(TeamRecord left, TeamRecord right) {
    final int byDate = left.createdAt.compareTo(right.createdAt);
    if (byDate != 0) return byDate;
    return left.id.compareTo(right.id);
  }

  static int _compareMembers(TeamMember left, TeamMember right) {
    if (left.role == TeamRole.owner) return -1;
    if (right.role == TeamRole.owner) return 1;
    final int byDate = left.createdAt.compareTo(right.createdAt);
    if (byDate != 0) return byDate;
    return left.userId.compareTo(right.userId);
  }
}
