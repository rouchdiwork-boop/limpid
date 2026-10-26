/// Les équipes de l'auteur : leurs membres, leurs rôles et leurs sièges.
///
/// Le contrat vit dans la couche domaine : l'écran des équipes le nomme,
/// l'implémentation de la couche données le réalise — aucun des deux ne
/// connaît l'autre. Les types qu'il manipule sont **immuables** : l'écran
/// lit un état, il ne le modifie jamais.
///
/// Les rôles portent les noms que le serveur publie : `owner`, `coAuthor`,
/// `betaReader` et `reader`. Le nom de l'énumération est donc le nom de la
/// route : l'implémentation envoie `role.name` et le serveur le reconnaît.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:limpid_app/src/domain/providers.dart';

/// Le rôle qu'un membre détient dans une équipe (D-16).
enum TeamRole {
  /// Le propriétaire de l'équipe : il invite, change les rôles et supprime
  /// l'équipe.
  ///
  /// Le rôle ne s'attribue pas : le serveur le réserve au créateur de
  /// l'équipe.
  owner,

  /// Le co-auteur : il édite les manuscrits.
  coAuthor,

  /// Le bêta-lecteur : il ne fait que commenter.
  betaReader,

  /// Le lecteur : il ne lit que.
  reader;

  /// Le rôle portant le nom [raw], `null` quand le nom est inconnu.
  ///
  /// Le serveur connaît un rôle de plus — l'invité externe, qui accède à
  /// l'équipe par un lien public. L'interface n'a pas de libellé pour lui :
  /// elle ne l'attribue donc jamais et le lit comme [reader], le rôle le plus
  /// prudent.
  static TeamRole? parse(String raw) {
    for (final TeamRole role in TeamRole.values) {
      if (role.name == raw) return role;
    }
    return null;
  }
}

/// Les rôles que l'interface attribue à un membre.
///
/// Le propriétaire est le créateur de l'équipe : son rôle ne s'attribue pas.
const List<TeamRole> assignableTeamRoles = <TeamRole>[
  TeamRole.coAuthor,
  TeamRole.betaReader,
  TeamRole.reader,
];

/// Une équipe, telle que le serveur la publie.
final class Team {
  /// Crée une équipe.
  const Team({
    required this.id,
    required this.name,
    required this.ownerId,
    required this.createdAt,
    required this.updatedAt,
  });

  /// L'identifiant de l'équipe.
  final String id;

  /// Le nom de l'équipe.
  final String name;

  /// L'identifiant du compte propriétaire de l'équipe.
  final String ownerId;

  /// L'instant de la création de l'équipe.
  final DateTime createdAt;

  /// L'instant de la dernière modification de l'équipe.
  final DateTime updatedAt;
}

/// Un membre d'équipe, avec le rôle qu'il y détient.
final class TeamMember {
  /// Crée un membre.
  const TeamMember({
    required this.teamId,
    required this.userId,
    required this.role,
    required this.createdAt,
  });

  /// L'identifiant de l'équipe.
  final String teamId;

  /// L'identifiant du compte membre.
  final String userId;

  /// Le rôle du membre dans l'équipe.
  final TeamRole role;

  /// L'instant de l'entrée du membre dans l'équipe.
  final DateTime createdAt;

  /// Indique que le membre occupe un siège de l'équipe.
  ///
  /// Le propriétaire ne prend pas de siège : les sièges sont les membres
  /// invités.
  bool get takesSeat => role != TeamRole.owner;
}

/// L'invitation d'un compte dans une équipe.
///
/// Le serveur ajoute le membre dès l'invitation : la trace conserve qui a
/// invité qui, avec quel rôle et quand.
final class TeamInvitation {
  /// Crée une invitation.
  const TeamInvitation({
    required this.id,
    required this.teamId,
    required this.userId,
    required this.role,
    required this.invitedBy,
    required this.createdAt,
  });

  /// L'identifiant de l'invitation.
  final String id;

  /// L'identifiant de l'équipe.
  final String teamId;

  /// L'identifiant du compte invité.
  final String userId;

  /// Le rôle accordé à l'invité.
  final TeamRole role;

  /// L'identifiant du compte qui a invité.
  final String invitedBy;

  /// L'instant de l'invitation.
  final DateTime createdAt;
}

/// L'état d'une invitation par adresse.
///
/// L'état `expired` n'est jamais écrit par le serveur : il se déduit de la
/// date d'expiration, au moment de la lecture.
enum TeamInvitationStatus {
  /// L'invitation attend une réponse : elle peut encore être acceptée.
  pending,

  /// L'invitation a été acceptée : le compte fait partie de l'équipe.
  accepted,

  /// L'invitation a été révoquée par le propriétaire.
  revoked,

  /// L'invitation a expiré : elle n'est plus en attente.
  expired;

  /// L'état portant le nom [raw], `null` quand le nom est inconnu.
  static TeamInvitationStatus? parse(String raw) {
    for (final TeamInvitationStatus status in TeamInvitationStatus.values) {
      if (status.name == raw) return status;
    }
    return null;
  }
}

/// L'invitation d'une adresse, en attente de réponse.
///
/// L'invitation attend : le membre n'entre dans l'équipe qu'à
/// l'acceptation, et l'invitation expire si personne ne répond.
final class TeamEmailInvitation {
  /// Crée une invitation.
  const TeamEmailInvitation({
    required this.id,
    required this.teamId,
    required this.email,
    required this.role,
    required this.status,
    required this.invitedBy,
    required this.createdAt,
    required this.expiresAt,
    this.acceptedAt,
    this.acceptedBy,
  });

  /// L'identifiant de l'invitation.
  final String id;

  /// L'identifiant de l'équipe visée.
  final String teamId;

  /// L'adresse invitée.
  final String email;

  /// Le rôle accordé à l'invité.
  final TeamRole role;

  /// L'état de l'invitation.
  final TeamInvitationStatus status;

  /// L'identifiant du compte qui a invité.
  final String invitedBy;

  /// L'instant de la création.
  final DateTime createdAt;

  /// L'instant d'expiration de l'invitation.
  final DateTime expiresAt;

  /// L'instant de l'acceptation, `null` quand l'invitation n'a pas été
  /// acceptée.
  final DateTime? acceptedAt;

  /// L'identifiant du compte qui a accepté, `null` quand l'invitation n'a
  /// pas été acceptée.
  final String? acceptedBy;

  /// L'invitation attend-elle encore une réponse.
  bool get isPending => status == TeamInvitationStatus.pending;

  /// Renvoie une copie de l'invitation avec les champs remplacés.
  ///
  /// La copie est immutable : l'écran lit un état, il ne le modifie jamais.
  TeamEmailInvitation copyWith({
    TeamInvitationStatus? status,
    DateTime? acceptedAt,
    String? acceptedBy,
  }) {
    return TeamEmailInvitation(
      id: id,
      teamId: teamId,
      email: email,
      role: role,
      status: status ?? this.status,
      invitedBy: invitedBy,
      createdAt: createdAt,
      expiresAt: expiresAt,
      acceptedAt: acceptedAt ?? this.acceptedAt,
      acceptedBy: acceptedBy ?? this.acceptedBy,
    );
  }

  /// L'invitation a-t-elle expiré.
  bool get isExpired => status == TeamInvitationStatus.expired;

  /// L'invitation a-t-elle été révoquée.
  bool get isRevoked => status == TeamInvitationStatus.revoked;

  /// L'invitation a-t-elle été acceptée.
  bool get isAccepted => status == TeamInvitationStatus.accepted;
}

/// L'invitation par adresse, et son lien quand il n'est pas parti.
///
/// Le lien n'est rendu que lorsqu'aucun fournisseur de courriel n'est
/// configuré : il est alors montré **une seule fois**, comme le jeton d'un
/// partage.
final class CreatedTeamInvitation {
  /// Crée un résultat.
  const CreatedTeamInvitation({required this.invitation, this.link});

  /// L'invitation créée.
  final TeamEmailInvitation invitation;

  /// Le lien d'acceptation, `null` quand le courriel est parti.
  final String? link;
}

/// Le port des équipes.
///
/// L'écran des équipes lit ce port et n'atteint jamais le serveur. La
/// doublure par défaut refuse les appels et dit pourquoi : un écran ne
/// présente jamais une équipe qu'il n'a pas lue.
abstract interface class TeamRepository {
  /// Les équipes dont le compte est membre.
  ///
  /// Lève une erreur typée quand le serveur refuse la lecture ou ne peut
  /// pas être atteint.
  Future<List<Team>> listTeams();

  /// Crée une équipe dont le compte est le propriétaire.
  ///
  /// Le propriétaire ne prend pas de siège : l'équipe n'a que ses membres
  /// invités pour compte.
  Future<Team> createTeam({required String name});

  /// Les membres de l'équipe [teamId] et le rôle de chacun.
  ///
  /// Une équipe qui n'existe pas et une équipe d'un autre compte répondent
  /// la même chose : le serveur répond 404, jamais une liste vide.
  Future<List<TeamMember>> listMembers({required String teamId});

  /// Invite le compte [userId] dans l'équipe [teamId] avec le rôle [role].
  ///
  /// Le serveur refuse l'invitation quand la formule n'accorde plus de siège
  /// et quand le compte est déjà membre de l'équipe.
  Future<TeamInvitation> invite({
    required String teamId,
    required String userId,
    required TeamRole role,
  });

  /// Invite l'adresse [email] dans l'équipe [teamId] avec le rôle [role].
  ///
  /// L'invitation **attend** : le membre n'entre dans l'équipe qu'à
  /// l'acceptation, et l'invitation expire si personne ne répond.
  ///
  /// Le lien d'acceptation est rendu **une seule fois**, et seulement quand
  /// aucun fournisseur de courriel n'est configuré : quand le courriel part,
  /// le lien n'est plus rendu.
  Future<CreatedTeamInvitation> inviteByEmail({
    required String teamId,
    required String email,
    required TeamRole role,
  });

  /// Les invitations de l'équipe [teamId], avec leur état.
  Future<List<TeamEmailInvitation>> listInvitations({required String teamId});

  /// Révoque l'invitation [invitationId] de l'équipe [teamId].
  ///
  /// Une invitation révoquée ne s'accepte plus.
  Future<TeamEmailInvitation> revokeInvitation({
    required String teamId,
    required String invitationId,
  });

  /// Accepte l'invitation que porte le jeton [token].
  ///
  /// Le serveur refuse l'acceptation quand le jeton est inconnu, expiré,
  /// révoqué ou déjà accepté : il répond la même chose dans les quatre cas.
  Future<TeamEmailInvitation> acceptInvitation({required String token});

  /// Change le rôle de [userId] dans l'équipe [teamId].
  ///
  /// Le rôle du propriétaire ne se change pas : le serveur le refuse.
  Future<TeamMember> changeRole({
    required String teamId,
    required String userId,
    required TeamRole role,
  });

  /// Retire le compte [userId] de l'équipe [teamId].
  ///
  /// Le propriétaire retire un membre, un membre quitte l'équipe lui-même.
  Future<void> removeMember({required String teamId, required String userId});

  /// Supprime l'équipe [teamId].
  ///
  /// Seul son propriétaire le peut.
  Future<void> deleteTeam({required String teamId});
}

/// Une [TeamRepository] qui ne peut pas atteindre le serveur.
///
/// Le mode démonstration n'a pas de service distant : l'écran des équipes le
/// dit au lieu de montrer une équipe qu'il n'a jamais lue.
final class UnavailableTeamRepository
    implements TeamRepository, UnavailableService {
  /// Crée le dépôt indisponible.
  const UnavailableTeamRepository();

  @override
  Future<List<Team>> listTeams() async =>
      throw const ServiceUnavailableException();

  @override
  Future<Team> createTeam({required String name}) async =>
      throw const ServiceUnavailableException();

  @override
  Future<List<TeamMember>> listMembers({required String teamId}) async =>
      throw const ServiceUnavailableException();

  @override
  Future<TeamInvitation> invite({
    required String teamId,
    required String userId,
    required TeamRole role,
  }) async => throw const ServiceUnavailableException();

  @override
  Future<CreatedTeamInvitation> inviteByEmail({
    required String teamId,
    required String email,
    required TeamRole role,
  }) async => throw const ServiceUnavailableException();

  @override
  Future<List<TeamEmailInvitation>> listInvitations({
    required String teamId,
  }) async => throw const ServiceUnavailableException();

  @override
  Future<TeamEmailInvitation> revokeInvitation({
    required String teamId,
    required String invitationId,
  }) async => throw const ServiceUnavailableException();

  @override
  Future<TeamEmailInvitation> acceptInvitation({required String token}) async =>
      throw const ServiceUnavailableException();

  @override
  Future<TeamMember> changeRole({
    required String teamId,
    required String userId,
    required TeamRole role,
  }) async => throw const ServiceUnavailableException();

  @override
  Future<void> removeMember({
    required String teamId,
    required String userId,
  }) async => throw const ServiceUnavailableException();

  @override
  Future<void> deleteTeam({required String teamId}) async =>
      throw const ServiceUnavailableException();
}

/// Le dépôt des équipes.
///
/// Le point de composition le remplace par l'implémentation de la couche
/// données. Le défaut refuse les appels et dit pourquoi : un écran ne
/// présente jamais une équipe qu'il n'a pas lue.
final Provider<TeamRepository> teamRepositoryProvider =
    Provider<TeamRepository>((Ref ref) => const UnavailableTeamRepository());
