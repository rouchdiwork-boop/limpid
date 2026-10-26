import 'package:limpid_app/src/domain/plan_repository.dart';
import 'package:limpid_app/src/domain/providers.dart';
import 'package:limpid_app/src/domain/team_repository.dart';
import 'package:limpid_core/limpid_core.dart';

/// L'instant des enregistrements du test.
final DateTime fakeMoment = DateTime.utc(2026, 11, 1);

/// L'équipe du compte, celle que le test montre.
final Team fakeTeam = Team(
  id: 'team-1',
  name: 'La Brigade',
  ownerId: 'owner-1',
  createdAt: fakeMoment,
  updatedAt: fakeMoment,
);

/// Le propriétaire de l'équipe du test.
final TeamMember fakeOwner = TeamMember(
  teamId: 'team-1',
  userId: 'owner-1',
  role: TeamRole.owner,
  createdAt: fakeMoment,
);

/// Le co-auteur de l'équipe du test.
final TeamMember fakeCoAuthor = TeamMember(
  teamId: 'team-1',
  userId: 'member-2',
  role: TeamRole.coAuthor,
  createdAt: fakeMoment,
);

/// A [TeamRepository] the test drives by hand.
///
/// The fake holds the teams, the members and the failures the test gives to
/// the screen: it reads nothing from the server.
final class FakeTeamRepository implements TeamRepository {
  /// Creates a repository.
  FakeTeamRepository({
    List<Team>? teams,
    Map<String, List<TeamMember>>? members,
  }) : teams = teams ?? <Team>[fakeTeam],
       members =
           members ??
           <String, List<TeamMember>>{
             fakeTeam.id: <TeamMember>[fakeOwner, fakeCoAuthor],
           };

  /// The teams the repository serves.
  List<Team> teams;

  /// The members of each team.
  Map<String, List<TeamMember>> members;

  /// The invitations by address of each team.
  Map<String, List<TeamEmailInvitation>> emailInvitations =
      <String, List<TeamEmailInvitation>>{};

  /// The link the server renders when it has no mail provider.
  String? invitationLink;

  /// The error every read throws when it is set.
  Object? error;

  /// The error the invitations throw when it is set.
  Object? inviteError;

  /// The error the changes of role throw when it is set.
  Object? changeRoleError;

  /// The names of the teams the author created.
  final List<String> createdNames = <String>[];

  /// The invitations the author sent.
  final List<TeamInvitation> invitations = <TeamInvitation>[];

  /// The roles the author changed, with the account they concern.
  final List<(String, TeamRole)> roleChanges = <(String, TeamRole)>[];

  /// The accounts the author removed from a team.
  final List<String> removals = <String>[];

  /// The teams the author deleted.
  final List<String> deletions = <String>[];

  @override
  Future<List<Team>> listTeams() async {
    final Object? failure = error;
    if (failure != null) throw failure;
    return List<Team>.unmodifiable(teams);
  }

  @override
  Future<Team> createTeam({required String name}) async {
    final Object? failure = error;
    if (failure != null) throw failure;
    createdNames.add(name);

    final Team team = Team(
      id: 'team-${teams.length + 1}',
      name: name,
      ownerId: 'owner-1',
      createdAt: fakeMoment,
      updatedAt: fakeMoment,
    );
    teams = <Team>[...teams, team];
    members = <String, List<TeamMember>>{
      ...members,
      team.id: <TeamMember>[
        TeamMember(
          teamId: team.id,
          userId: 'owner-1',
          role: TeamRole.owner,
          createdAt: fakeMoment,
        ),
      ],
    };
    return team;
  }

  @override
  Future<List<TeamMember>> listMembers({required String teamId}) async {
    final Object? failure = error;
    if (failure != null) throw failure;
    return List<TeamMember>.unmodifiable(
      members[teamId] ?? const <TeamMember>[],
    );
  }

  @override
  Future<TeamInvitation> invite({
    required String teamId,
    required String userId,
    required TeamRole role,
  }) async {
    final Object? failure = inviteError ?? error;
    if (failure != null) throw failure;

    final TeamInvitation invitation = TeamInvitation(
      id: 'invitation-${invitations.length + 1}',
      teamId: teamId,
      userId: userId,
      role: role,
      invitedBy: 'owner-1',
      createdAt: fakeMoment,
    );
    invitations.add(invitation);

    final List<TeamMember> current = members[teamId] ?? <TeamMember>[];
    members = <String, List<TeamMember>>{
      ...members,
      teamId: <TeamMember>[
        ...current,
        TeamMember(
          teamId: teamId,
          userId: userId,
          role: role,
          createdAt: fakeMoment,
        ),
      ],
    };
    return invitation;
  }

  @override
  Future<CreatedTeamInvitation> inviteByEmail({
    required String teamId,
    required String email,
    required TeamRole role,
  }) async {
    final Object? failure = inviteError ?? error;
    if (failure != null) throw failure;

    final TeamEmailInvitation invitation = TeamEmailInvitation(
      id: 'email-invitation-${emailInvitations.length + 1}',
      teamId: teamId,
      email: email,
      role: role,
      status: TeamInvitationStatus.pending,
      invitedBy: 'owner-1',
      createdAt: fakeMoment,
      expiresAt: fakeMoment.add(const Duration(days: 7)),
    );
    emailInvitations = <String, List<TeamEmailInvitation>>{
      ...emailInvitations,
      teamId: <TeamEmailInvitation>[
        ...(emailInvitations[teamId] ?? const <TeamEmailInvitation>[]),
        invitation,
      ],
    };
    return CreatedTeamInvitation(invitation: invitation, link: invitationLink);
  }

  @override
  Future<List<TeamEmailInvitation>> listInvitations({
    required String teamId,
  }) async {
    final Object? failure = error;
    if (failure != null) throw failure;
    return List<TeamEmailInvitation>.unmodifiable(
      emailInvitations[teamId] ?? const <TeamEmailInvitation>[],
    );
  }

  @override
  Future<TeamEmailInvitation> revokeInvitation({
    required String teamId,
    required String invitationId,
  }) async {
    final Object? failure = inviteError ?? error;
    if (failure != null) throw failure;

    final List<TeamEmailInvitation> current =
        emailInvitations[teamId] ?? const <TeamEmailInvitation>[];
    final TeamEmailInvitation revoked = current
        .firstWhere(
          (TeamEmailInvitation invitation) => invitation.id == invitationId,
        )
        .copyWith(status: TeamInvitationStatus.revoked);
    emailInvitations = <String, List<TeamEmailInvitation>>{
      ...emailInvitations,
      teamId: <TeamEmailInvitation>[
        for (final TeamEmailInvitation invitation in current)
          if (invitation.id == invitationId) revoked else invitation,
      ],
    };
    return revoked;
  }

  @override
  Future<TeamEmailInvitation> acceptInvitation({required String token}) async {
    final Object? failure = inviteError ?? error;
    if (failure != null) throw failure;

    final TeamEmailInvitation accepted = TeamEmailInvitation(
      id: 'accepted-$token',
      teamId: fakeTeam.id,
      email: 'invite@example.com',
      role: TeamRole.coAuthor,
      status: TeamInvitationStatus.accepted,
      invitedBy: 'owner-1',
      createdAt: fakeMoment,
      expiresAt: fakeMoment.add(const Duration(days: 7)),
      acceptedAt: fakeMoment,
      acceptedBy: 'member-3',
    );
    return accepted;
  }

  @override
  Future<TeamMember> changeRole({
    required String teamId,
    required String userId,
    required TeamRole role,
  }) async {
    final Object? failure = changeRoleError ?? error;
    if (failure != null) throw failure;
    roleChanges.add((userId, role));

    final List<TeamMember> current = members[teamId] ?? <TeamMember>[];
    final List<TeamMember> updated = <TeamMember>[
      for (final TeamMember member in current)
        if (member.userId == userId)
          TeamMember(
            teamId: member.teamId,
            userId: member.userId,
            role: role,
            createdAt: member.createdAt,
          )
        else
          member,
    ];
    members = <String, List<TeamMember>>{...members, teamId: updated};
    return updated.firstWhere((TeamMember member) => member.userId == userId);
  }

  @override
  Future<void> removeMember({
    required String teamId,
    required String userId,
  }) async {
    final Object? failure = error;
    if (failure != null) throw failure;
    removals.add(userId);

    final List<TeamMember> current = members[teamId] ?? <TeamMember>[];
    members = <String, List<TeamMember>>{
      ...members,
      teamId: <TeamMember>[
        for (final TeamMember member in current)
          if (member.userId != userId) member,
      ],
    };
  }

  @override
  Future<void> deleteTeam({required String teamId}) async {
    final Object? failure = error;
    if (failure != null) throw failure;
    deletions.add(teamId);
    teams = <Team>[
      for (final Team team in teams)
        if (team.id != teamId) team,
    ];
  }
}

/// A [PlanRepository] the test drives by hand.
///
/// The teams screen reads the formula of the account to know the number of
/// seats it grants: the fake holds that number.
final class FakePlanRepository implements PlanRepository {
  /// Creates a repository.
  FakePlanRepository({this.seatCount = 5});

  /// The number of seats the formula grants to a team.
  final int seatCount;

  @override
  Future<AccountPlan> currentPlan() async => AccountPlan(
    plan: SubscriptionPlan.studio,
    displayName: 'Studio',
    status: PlanStatus.active,
    period: BillingPeriod.monthly,
    periodStartedAt: fakeMoment,
    seatCount: seatCount,
  );

  @override
  Future<List<PlanOffer>> offers() async =>
      throw const ServiceUnavailableException();

  @override
  Future<List<QuotaReading>> usage() async =>
      throw const ServiceUnavailableException();

  @override
  Future<AccountPlan> changePlan({
    required SubscriptionPlan plan,
    required BillingPeriod period,
  }) async => throw const ServiceUnavailableException();

  @override
  Future<CheckoutSession> openCheckout({
    required SubscriptionPlan plan,
    required BillingPeriod period,
    required Uri returnTo,
  }) async => throw const ServiceUnavailableException();
}

/// A [PlanRepository] the server refuses to answer.
///
/// The teams screen reads the formula of the account to know the number of
/// seats it grants: when the formula fails, the screen shows the seats it
/// counted without inventing a limit.
final class FailingPlanRepository implements PlanRepository {
  /// Creates a repository.
  const FailingPlanRepository();

  @override
  Future<AccountPlan> currentPlan() async =>
      throw const ServiceUnavailableException();

  @override
  Future<List<PlanOffer>> offers() async =>
      throw const ServiceUnavailableException();

  @override
  Future<List<QuotaReading>> usage() async =>
      throw const ServiceUnavailableException();

  @override
  Future<AccountPlan> changePlan({
    required SubscriptionPlan plan,
    required BillingPeriod period,
  }) async => throw const ServiceUnavailableException();

  @override
  Future<CheckoutSession> openCheckout({
    required SubscriptionPlan plan,
    required BillingPeriod period,
    required Uri returnTo,
  }) async => throw const ServiceUnavailableException();
}
