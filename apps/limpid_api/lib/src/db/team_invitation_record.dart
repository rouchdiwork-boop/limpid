/// L'invitation d'équipe en attente, et l'état de son cycle de vie.
///
/// Une invitation **par courriel** est un objet : elle porte une adresse, un
/// rôle, une date d'expiration et l'empreinte d'un jeton. Le jeton n'est
/// jamais stocké en clair : la base n'en garde que l'empreinte, exactement
/// comme elle fait des partages en lecture.
///
/// Le membre n'est ajouté à l'équipe qu'à l'acceptation : une invitation
/// qui expire est une invitation qui attend.
library;

import 'team_record.dart';

/// L'état d'une invitation d'équipe.
///
/// Trois états sont **écrits** dans la base : `pending`, `accepted` et
/// `revoked`. Le quatrième, `expired`, est **calculé** à la lecture : il n'y
/// a pas d'ordonnanceur dans l'API, et une invitation qui expire reste en
/// attente dans la base jusqu'à ce qu'on la regarde.
enum TeamInvitationStatus {
  /// L'invitation attend une réponse : elle peut encore être acceptée.
  pending('pending'),

  /// L'invitation a été acceptée : le compte fait partie de l'équipe.
  accepted('accepted'),

  /// L'invitation a été révoquée par le propriétaire de l'équipe.
  revoked('revoked'),

  /// L'invitation a expiré : elle n'est plus en attente.
  ///
  /// Cet état n'est jamais écrit dans la base : il se déduit de la date
  /// d'expiration, comme pour un partage en lecture.
  expired('expired');

  const TeamInvitationStatus(this.label);

  /// Le nom de l'état, tel que l'API le publie.
  final String label;

  /// L'état portant le nom [raw], `null` quand le nom est inconnu.
  static TeamInvitationStatus? parse(String raw) {
    for (final TeamInvitationStatus status in TeamInvitationStatus.values) {
      if (status.name == raw) return status;
    }
    return null;
  }
}

/// Une invitation d'équipe en attente, telle que la base la stocke.
///
/// L'invitation porte l'adresse invitée, le rôle accordé, l'empreinte du
/// jeton et les dates de création, d'expiration et d'acceptation. Le jeton
/// lui-même n'existe que dans la réponse de la création : il est montré une
/// seule fois.
final class TeamInvitationRecord {
  /// Crée une invitation.
  const TeamInvitationRecord({
    required this.id,
    required this.teamId,
    required this.email,
    required this.role,
    required this.tokenHash,
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

  /// L'adresse invitée, normalisée.
  final String email;

  /// Le rôle accordé à l'invité.
  final TeamRole role;

  /// L'empreinte du jeton : le jeton lui-même n'est jamais stocké.
  final String tokenHash;

  /// L'état écrit de l'invitation.
  ///
  /// La valeur `expired` n'est jamais écrite : elle se déduit à la lecture.
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

  /// Indique si l'invitation a expiré à l'instant [now].
  ///
  /// L'échéance est inclusive : à l'instant exact de l'échéance,
  /// l'invitation a expiré.
  bool isExpiredAt(DateTime now) => !now.toUtc().isBefore(expiresAt.toUtc());

  /// Indique si l'invitation attend encore une réponse à l'instant [now].
  ///
  /// Une invitation expirée, révoquée ou déjà acceptée n'attend plus rien :
  /// elle ne peut pas être réactivée.
  bool isPendingAt(DateTime now) {
    return status == TeamInvitationStatus.pending && !isExpiredAt(now);
  }

  /// L'état que l'invitation présente à l'instant [now].
  ///
  /// L'état `expired` se déduit de la date d'expiration : il n'est jamais
  /// écrit dans la base.
  TeamInvitationStatus effectiveStatusAt(DateTime now) {
    if (status == TeamInvitationStatus.pending && isExpiredAt(now)) {
      return TeamInvitationStatus.expired;
    }
    return status;
  }

  /// Renvoie une copie de l'invitation avec les champs remplacés.
  ///
  /// La révocation est irréversible : [status] ne peut pas repasser de
  /// `revoked` à `pending` par cette méthode.
  TeamInvitationRecord copyWith({
    TeamInvitationStatus? status,
    DateTime? acceptedAt,
    String? acceptedBy,
  }) {
    return TeamInvitationRecord(
      id: id,
      teamId: teamId,
      email: email,
      role: role,
      tokenHash: tokenHash,
      status: status ?? this.status,
      invitedBy: invitedBy,
      createdAt: createdAt,
      expiresAt: expiresAt,
      acceptedAt: acceptedAt ?? this.acceptedAt,
      acceptedBy: acceptedBy ?? this.acceptedBy,
    );
  }

  /// La représentation JSON envoyée aux clients.
  ///
  /// L'empreinte du jeton n'y figure jamais : la liste des invitations doit
  /// pouvoir être montrée sans rien divulguer du secret.
  ///
  /// L'état publié est l'état **effectif** : une invitation expirée est
  /// publiée comme expirée, même si la base dit encore `pending`.
  Map<String, Object?> toJson({DateTime? now}) {
    final DateTime moment = (now ?? DateTime.now()).toUtc();
    return <String, Object?>{
      'id': id,
      'team_id': teamId,
      'email': email,
      'role': role.name,
      'status': effectiveStatusAt(moment).name,
      'invited_by': invitedBy,
      'created_at': createdAt.toUtc().toIso8601String(),
      'expires_at': expiresAt.toUtc().toIso8601String(),
      'accepted_at': acceptedAt?.toUtc().toIso8601String(),
      'accepted_by': acceptedBy,
    };
  }
}

/// Le résultat de l'acceptation d'une invitation.
enum InvitationAcceptanceOutcome {
  /// Le membre a été ajouté à l'équipe.
  accepted('accepted'),

  /// La formule du compte n'accorde plus de siège : l'invitation reste en
  /// attente.
  noSeat('no_seat'),

  /// L'invitation n'est plus en attente : elle a déjà été utilisée.
  alreadyUsed('already_used');

  const InvitationAcceptanceOutcome(this.label);

  /// Le nom du résultat.
  final String label;
}
