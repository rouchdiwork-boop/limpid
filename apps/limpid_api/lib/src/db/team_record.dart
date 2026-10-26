/// Le rôle qu'un membre détient dans une équipe (D-16).
///
/// Les quatre premiers rôles reprennent les valeurs de `ProjectRole` : le
/// rôle d'équipe et le rôle sur un projet décrivent les mêmes niveaux de
/// collaboration. Le rôle d'équipe reste un rôle distinct : il décrit ce
/// qu'un membre peut faire dans l'équipe, pas dans un projet.
enum TeamRole {
  /// Le propriétaire de l'équipe : il invite, change les rôles et supprime
  /// l'équipe.
  owner('propriétaire'),

  /// Le co-auteur : il édite les manuscrits.
  coAuthor('co-auteur'),

  /// Le bêta-lecteur : il ne fait que commenter.
  betaReader('beta-lecteur'),

  /// Le lecteur : il ne lit que.
  reader('lecteur'),

  /// L'invité externe : il accède à l'équipe par un lien public limité.
  externalGuest('invité externe');

  const TeamRole(this.label);

  /// Le libellé du rôle, en français.
  final String label;

  /// Le rôle portant le nom [raw], `null` quand le nom est inconnu.
  static TeamRole? parse(String raw) {
    for (final TeamRole role in TeamRole.values) {
      if (role.name == raw) return role;
    }
    return null;
  }
}

/// Une équipe, telle que la base la stocke.
final class TeamRecord {
  /// Crée une équipe.
  const TeamRecord({
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

  /// Le compte propriétaire de l'équipe.
  final String ownerId;

  /// L'instant de création.
  final DateTime createdAt;

  /// L'instant de la dernière modification.
  final DateTime updatedAt;

  /// La représentation JSON envoyée aux clients.
  Map<String, Object?> toJson() {
    return <String, Object?>{
      'id': id,
      'name': name,
      'owner_id': ownerId,
      'created_at': createdAt.toUtc().toIso8601String(),
      'updated_at': updatedAt.toUtc().toIso8601String(),
    };
  }
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

  /// L'instant de l'entrée dans l'équipe.
  final DateTime createdAt;

  /// Renvoie une copie du membre avec le rôle remplacé.
  TeamMember copyWith({TeamRole? role}) {
    return TeamMember(
      teamId: teamId,
      userId: userId,
      role: role ?? this.role,
      createdAt: createdAt,
    );
  }

  /// La représentation JSON envoyée aux clients.
  Map<String, Object?> toJson() {
    return <String, Object?>{
      'team_id': teamId,
      'user_id': userId,
      'role': role.name,
      'created_at': createdAt.toUtc().toIso8601String(),
    };
  }
}

/// La trace d'une invitation d'équipe.
///
/// L'API ajoute le membre dès l'invitation : la ligne conserve qui a invité
/// qui, avec quel rôle et quand.
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

  /// La représentation JSON envoyée aux clients.
  Map<String, Object?> toJson() {
    return <String, Object?>{
      'id': id,
      'team_id': teamId,
      'user_id': userId,
      'role': role.name,
      'invited_by': invitedBy,
      'created_at': createdAt.toUtc().toIso8601String(),
    };
  }
}

/// Le résultat d'une invitation : le membre ajouté et la trace de
/// l'invitation.
final class MemberAddition {
  /// Crée un résultat d'invitation.
  const MemberAddition({required this.member, required this.invitation});

  /// Le membre ajouté à l'équipe.
  final TeamMember member;

  /// La trace de l'invitation.
  final TeamInvitation invitation;
}
