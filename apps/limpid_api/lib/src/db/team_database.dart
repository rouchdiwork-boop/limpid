import 'plan_lookup.dart';
import 'team_invitation_record.dart';
import 'team_record.dart';

export 'plan_lookup.dart';

/// Le port de persistance des équipes.
///
/// L'API ne parle jamais directement au moteur : elle passe par ce port, que
/// la suite de tests remplace par une implémentation en mémoire.
abstract interface class TeamDatabase {
  /// La lecture de la formule du compte.
  PlanLookup get planLookup;

  /// Liste les équipes dont [userId] est membre, les plus anciennes d'abord.
  Future<List<TeamRecord>> listTeams({required String userId});

  /// L'équipe [teamId], `null` quand elle n'existe pas.
  Future<TeamRecord?> findTeam({required String teamId});

  /// Renvoie le membre [userId] de l'équipe [teamId], `null` quand il n'en
  /// est pas membre.
  Future<TeamMember?> findMember({
    required String teamId,
    required String userId,
  });

  /// Liste les membres de l'équipe, le propriétaire en premier.
  Future<List<TeamMember>> listMembers({required String teamId});

  /// Crée l'équipe et son propriétaire.
  Future<TeamRecord> createTeam({
    required String ownerId,
    required String name,
  });

  /// Ajoute [userId] à l'équipe avec le rôle [role] et enregistre
  /// l'invitation.
  ///
  /// L'équipe n'accueille jamais plus de [maxSeats] membres invités : le
  /// compte des sièges et l'insertion se font dans la même transaction.
  /// Renvoie `null` quand la limite de sièges est atteinte.
  Future<MemberAddition?> addMember({
    required String teamId,
    required String userId,
    required TeamRole role,
    required String invitedBy,
    required int maxSeats,
  });

  /// Change le rôle d'un membre, `null` quand le membre n'existe pas.
  Future<TeamMember?> changeMemberRole({
    required String teamId,
    required String userId,
    required TeamRole role,
  });

  /// Retire un membre de l'équipe, `false` quand il n'en était pas membre.
  Future<bool> removeMember({required String teamId, required String userId});

  /// Supprime l'équipe, `false` quand elle n'existe pas.
  Future<bool> deleteTeam({required String teamId});

  /// Accepte l'invitation [invitationId] et ajoute le compte [userId] à
  /// l'équipe [teamId] avec le rôle [role].
  ///
  /// L'acceptation **consomme** l'invitation : elle ne peut être utilisée
  /// qu'une fois. Les sièges sont vérifiés au moment de l'acceptation, comme
  /// ils l'ont été à l'invitation : la formule a pu changer entre les deux.
  ///
  /// Renvoie [InvitationAcceptanceOutcome.accepted] quand le membre a été
  /// ajouté, [InvitationAcceptanceOutcome.noSeat] quand la formule
  /// n'accorde plus de siège — l'invitation reste alors en attente — et
  /// [InvitationAcceptanceOutcome.alreadyUsed] quand l'invitation n'est plus
  /// en attente.
  Future<InvitationAcceptanceOutcome> acceptInvitation({
    required String invitationId,
    required String teamId,
    required String userId,
    required TeamRole role,
    required String invitedBy,
    required int maxSeats,
  });
}
