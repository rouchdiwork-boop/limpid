import 'package:limpid_core/limpid_core.dart';

import '../db/team_database.dart';
import '../db/team_record.dart';
import '../errors/app_exception.dart';

/// Le service des équipes.
///
/// Le service porte les règles de D-16 : seul le propriétaire invite, change
/// les rôles et supprime l'équipe ; un appelant qui n'est pas membre
/// n'apprend jamais que l'équipe existe, la réponse est un 404 et jamais un
/// 403.
final class TeamService {
  /// Crée un service sur la base [database].
  const TeamService(this._database);

  final TeamDatabase _database;

  /// La formule « Gratuit », appliquée quand la formule est inconnue.
  static const SubscriptionPlan _freePlan = SubscriptionPlan.free;

  /// Les caractères accentués des libellés de formule.
  static const Map<String, String> _accents = <String, String>{
    'à': 'a',
    'â': 'a',
    'ä': 'a',
    'ç': 'c',
    'è': 'e',
    'é': 'e',
    'ê': 'e',
    'ë': 'e',
    'î': 'i',
    'ï': 'i',
    'ô': 'o',
    'ö': 'o',
    'ù': 'u',
    'û': 'u',
    'ü': 'u',
    'ÿ': 'y',
  };

  /// Liste les équipes dont [userId] est membre.
  Future<List<TeamRecord>> listTeams(String userId) {
    return _database.listTeams(userId: userId);
  }

  /// Crée une équipe dont [ownerId] est le propriétaire.
  Future<TeamRecord> createTeam({
    required String ownerId,
    required String name,
  }) {
    if (name.trim().isEmpty) {
      throw const ValidationException(
        field: 'name',
        message: 'Le nom de l\'équipe ne peut pas être vide.',
      );
    }
    return _database.createTeam(ownerId: ownerId, name: name);
  }

  /// Liste les membres de l'équipe [teamId] et le rôle de chacun.
  ///
  /// Seuls les membres voient la liste : un appelant extérieur reçoit un 404,
  /// exactement comme pour une équipe qui n'existe pas.
  Future<List<TeamMember>> listMembers({
    required String teamId,
    required String callerId,
  }) async {
    await _requireMember(teamId: teamId, callerId: callerId);
    return _database.listMembers(teamId: teamId);
  }

  /// Invite [userId] dans l'équipe [teamId] avec le rôle [role].
  ///
  /// Seul le propriétaire invite. Le propriétaire n'occupe pas de siège : les
  /// sièges sont les membres invités, et l'équipe n'en accueille pas plus
  /// que la formule du compte n'en accorde. Au-delà, l'invitation est
  /// refusée par une erreur qui nomme la limite atteinte.
  Future<TeamInvitation> invite({
    required String teamId,
    required String callerId,
    required String userId,
    required TeamRole role,
  }) async {
    await _requireOwner(
      teamId: teamId,
      callerId: callerId,
      action: 'inviter des membres',
    );
    _requireAssignableRole(role);

    final TeamMember? existing = await _database.findMember(
      teamId: teamId,
      userId: userId,
    );
    if (existing != null) {
      throw const ConflictException(
        message: 'Ce compte fait déjà partie de l\'équipe.',
      );
    }

    final SubscriptionPlan plan = await _planOf(callerId);
    final int maxSeats = PlanDefinition.of(plan).quota.maxSeats;
    final MemberAddition? addition = await _database.addMember(
      teamId: teamId,
      userId: userId,
      role: role,
      invitedBy: callerId,
      maxSeats: maxSeats,
    );
    if (addition == null) {
      throw _seatLimitExceeded(plan, maxSeats);
    }
    return addition.invitation;
  }

  /// Change le rôle de [userId] dans l'équipe [teamId].
  ///
  /// Seul le propriétaire change les rôles, et le rôle du propriétaire
  /// lui-même ne se change pas.
  Future<TeamMember> changeRole({
    required String teamId,
    required String callerId,
    required String userId,
    required TeamRole role,
  }) async {
    await _requireOwner(
      teamId: teamId,
      callerId: callerId,
      action: 'changer les rôles',
    );
    _requireAssignableRole(role);

    final TeamMember? target = await _database.findMember(
      teamId: teamId,
      userId: userId,
    );
    if (target == null) throw const NotFoundException();
    if (target.role == TeamRole.owner) {
      throw const ConflictException(
        message:
            'Le rôle du propriétaire de l\'équipe ne peut pas être modifié : '
            'supprimez l\'équipe si vous voulez repartir de zéro.',
      );
    }

    final TeamMember? updated = await _database.changeMemberRole(
      teamId: teamId,
      userId: userId,
      role: role,
    );
    if (updated == null) throw const NotFoundException();
    return updated;
  }

  /// Retire [userId] de l'équipe [teamId].
  ///
  /// Le propriétaire retire un membre, un membre quitte l'équipe lui-même.
  Future<void> removeMember({
    required String teamId,
    required String callerId,
    required String userId,
  }) async {
    final TeamMember caller = await _requireMember(
      teamId: teamId,
      callerId: callerId,
    );
    final bool isSelf = caller.userId == userId;
    if (!isSelf && caller.role != TeamRole.owner) {
      throw const ForbiddenException(
        message: 'Seul le propriétaire de l\'équipe peut retirer un membre.',
      );
    }

    final TeamMember? target = await _database.findMember(
      teamId: teamId,
      userId: userId,
    );
    if (target == null) throw const NotFoundException();
    if (target.role == TeamRole.owner) {
      throw const ConflictException(
        message:
            'Le propriétaire ne peut pas quitter son équipe : '
            'supprimez l\'équipe.',
      );
    }

    await _database.removeMember(teamId: teamId, userId: userId);
  }

  /// Supprime l'équipe [teamId]. Seul son propriétaire le peut.
  Future<void> deleteTeam({
    required String teamId,
    required String callerId,
  }) async {
    await _requireOwner(
      teamId: teamId,
      callerId: callerId,
      action: 'supprimer l\'équipe',
    );
    final bool deleted = await _database.deleteTeam(teamId: teamId);
    if (!deleted) throw const NotFoundException();
  }

  /// Le membre [callerId] de l'équipe [teamId].
  ///
  /// Une équipe qui n'existe pas et une équipe dont l'appelant n'est pas
  /// membre répondent la même chose : un 404, pour ne jamais divulguer
  /// l'existence d'une équipe.
  Future<TeamMember> _requireMember({
    required String teamId,
    required String callerId,
  }) async {
    final TeamMember? member = await _database.findMember(
      teamId: teamId,
      userId: callerId,
    );
    if (member == null) throw const NotFoundException();
    return member;
  }

  /// Le propriétaire de l'équipe [teamId].
  Future<TeamMember> _requireOwner({
    required String teamId,
    required String callerId,
    required String action,
  }) async {
    final TeamMember member = await _requireMember(
      teamId: teamId,
      callerId: callerId,
    );
    if (member.role != TeamRole.owner) {
      throw ForbiddenException(
        message: 'Seul le propriétaire de l\'équipe peut $action.',
      );
    }
    return member;
  }

  /// La formule du compte [userId].
  ///
  /// La lecture vient de la composition : le service ne connaît pas le
  /// fichier des formules. Une formule inconnue vaut « Gratuit ».
  Future<SubscriptionPlan> _planOf(String userId) async {
    final String? raw = await _database.planLookup(userId);
    return _parsePlan(raw);
  }

  /// La formule correspondant au nom [raw].
  ///
  /// Le nom peut être celui de l'énumération (`studio`) ou celui affiché par
  /// l'interface (`Studio`) : la comparaison ignore la casse, les accents et
  /// la parenthèse de la formule annuelle.
  static SubscriptionPlan _parsePlan(String? raw) {
    if (raw == null) return _freePlan;
    final String normalized = _normalize(raw);
    for (final SubscriptionPlan plan in SubscriptionPlan.values) {
      if (_normalize(plan.name) == normalized) return plan;
      if (_normalize(PlanDefinition.of(plan).displayName) == normalized) {
        return plan;
      }
    }
    return _freePlan;
  }

  /// Le nom [value] réduit à ses lettres et à ses chiffres.
  static String _normalize(String value) {
    final String base = value.toLowerCase().split('(').first;
    final StringBuffer buffer = StringBuffer();
    for (final String character in base.split('')) {
      final String folded = _accents[character] ?? character;
      if (RegExp('[a-z0-9]').hasMatch(folded)) buffer.write(folded);
    }
    return buffer.toString();
  }

  /// Le rôle [role] peut être attribué à un membre.
  ///
  /// Le propriétaire est le créateur de l'équipe : son rôle ne s'attribue
  /// pas.
  static void _requireAssignableRole(TeamRole role) {
    if (role == TeamRole.owner) {
      throw const ValidationException(
        field: 'role',
        message:
            'Le rôle « propriétaire » est réservé au créateur de l\'équipe.',
      );
    }
  }

  /// L'erreur refusant une invitation au-delà des sièges de la formule.
  ///
  /// La formule Studio est la plus haute : une équipe pleine est un conflit
  /// (409). Une formule plus basse exige un changement de formule (402).
  static AppException _seatLimitExceeded(SubscriptionPlan plan, int maxSeats) {
    final String seats = maxSeats > 1 ? '$maxSeats sièges' : '$maxSeats siège';
    if (plan == SubscriptionPlan.studio) {
      return ConflictException(
        message:
            'La formule Studio est limitée à $seats par équipe : '
            'retirez un membre avant d\'inviter quelqu\'un d\'autre.',
        details: <String, Object?>{
          'limit': maxSeats,
          'plan': PlanDefinition.of(plan).displayName,
        },
      );
    }
    return PlanLimitException(
      message:
          'Votre formule ${PlanDefinition.of(plan).displayName} ne comporte '
          'que $seats par équipe : la formule Studio est nécessaire pour '
          'inviter un membre de plus.',
      details: <String, Object?>{
        'limit': maxSeats,
        'plan': PlanDefinition.of(plan).displayName,
        'required_plan': PlanDefinition.of(SubscriptionPlan.studio).displayName,
      },
    );
  }
}
