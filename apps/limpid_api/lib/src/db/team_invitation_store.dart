/// Le port de persistance des invitations d'équipe en attente.
///
/// Le port ne porte aucune règle métier : l'échéance, la révocation et la
/// lecture du jeton vivent dans le service. Le magasin ne fait que garder
/// des lignes et les rendre.
///
/// Les invitations **immédiates** — celle qui vise un compte existant et
/// ajoute le membre sur-le-champ — sont écrites par la base des équipes
/// ([TeamDatabase]). Ce port ne connaît que les invitations **par
/// courriel**, celles qui attendent une réponse.
library;

import 'team_invitation_record.dart';

/// Le port de persistance des invitations d'équipe en attente.
abstract interface class TeamInvitationStore {
  /// L'invitation [id], `null` quand elle n'existe pas.
  Future<TeamInvitationRecord?> findById(String id);

  /// Les invitations par courriel de l'équipe [teamId], les plus récentes
  /// d'abord.
  ///
  /// La liste ne contient que les invitations par courriel : les traces
  /// des invitations immédiates ne sont pas des invitations en attente.
  Future<List<TeamInvitationRecord>> listByTeam({required String teamId});

  /// L'invitation en attente de l'équipe [teamId] pour l'adresse [email],
  /// `null` quand il n'y en a pas.
  Future<TeamInvitationRecord?> findPendingByEmail({
    required String teamId,
    required String email,
  });

  /// Enregistre une nouvelle invitation.
  Future<void> insert(TeamInvitationRecord record);

  /// Accepte l'invitation [id] pour le compte [userId].
  ///
  /// L'acceptation est **conditionnelle** : elle ne porte que sur une
  /// invitation encore en attente. Renvoie `false` quand l'invitation n'est
  /// plus en attente — le jeton ne marche qu'une fois.
  Future<bool> markAccepted({
    required String id,
    required String userId,
    required DateTime acceptedAt,
  });

  /// Révoque l'invitation [id] de l'équipe [teamId].
  ///
  /// Renvoie l'invitation après l'opération, `null` quand elle n'existe pas.
  /// Une invitation déjà révoquée est renvoyée telle quelle : la révocation
  /// est idempotente. Une invitation déjà acceptée n'est pas révoquée : elle
  /// porte un membre, elle n'est plus une invitation.
  Future<TeamInvitationRecord?> revoke({
    required String id,
    required String teamId,
  });
}
