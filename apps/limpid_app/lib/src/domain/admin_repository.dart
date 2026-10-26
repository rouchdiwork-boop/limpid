/// Le back-office : les comptes du service et les indicateurs de
/// fonctionnalité.
///
/// Le contrat vit dans la couche domaine : les écrans le nomment,
/// l'implémentation de la couche données le réalise — aucun des deux ne
/// connaît l'autre. Les types qu'il manipule sont **immuables** : l'écran
/// lit un état, il ne le modifie jamais.
///
/// Le serveur réserve ces lectures à l'administrateur. Un refus n'est donc
/// pas une panne : l'écran le dit, il ne montre jamais une liste vide qui
/// ferait croire que le service n'a aucun compte.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Un compte du service, tel que le back-office le connaît.
///
/// Le compte est désigné par son identifiant : les comptes vivent dans
/// l'identité du service, et l'API n'en connaît que l'identifiant.
///
/// Les compteurs portent l'usage du compte : ses projets, ses
/// collaborations, ses messages et ses opérations. Ils disent ce que le
/// compte a fait, jamais qui il est.
final class AdminAccount {
  /// Crée un compte.
  const AdminAccount({
    required this.userId,
    required this.plan,
    required this.projectCount,
    required this.collaborationCount,
    required this.commentCount,
    required this.operationCount,
    required this.lastActivityAt,
    required this.isPurged,
    this.email,
  });

  /// L'identifiant du compte.
  final String userId;

  /// L'adresse du compte, `null` quand le serveur ne la publie pas.
  ///
  /// L'API ne rend aujourd'hui que l'identifiant du compte : le champ est
  /// prévu pour le jour où elle rendra l'adresse, et il reste `null` en
  /// attendant. L'écran montre alors l'identifiant, jamais une adresse
  /// qu'il n'a pas lue.
  final String? email;

  /// La formule du compte, `null` quand le serveur ne la connaît pas.
  final String? plan;

  /// Le nombre de projets que le compte possède.
  final int projectCount;

  /// Le nombre de projets sur lesquels le compte collabore.
  final int collaborationCount;

  /// Le nombre de messages que le compte a écrits.
  final int commentCount;

  /// Le nombre d'opérations que le compte a poussées.
  final int operationCount;

  /// L'instant de la dernière activité du compte, `null` quand elle est
  /// inconnue.
  final DateTime? lastActivityAt;

  /// Indique si les données du compte ont été effacées pour toujours.
  final bool isPurged;
}

/// Un indicateur de fonctionnalité du service.
///
/// L'indicateur est lu à chaque appel : l'activer ne demande aucun
/// redéploiement, et le changement est visible aussitôt.
final class AdminFeatureFlag {
  /// Crée un indicateur.
  const AdminFeatureFlag({
    required this.key,
    required this.isEnabled,
    required this.description,
    required this.updatedAt,
    required this.updatedBy,
  });

  /// La clé technique de l'indicateur, par exemple `ai_premium`.
  final String key;

  /// Indique si l'indicateur est actif.
  final bool isEnabled;

  /// Ce que fait l'indicateur, en une phrase.
  final String description;

  /// L'instant du dernier changement de l'indicateur.
  final DateTime updatedAt;

  /// L'identifiant de l'administrateur qui a changé l'indicateur.
  final String updatedBy;

  /// Une copie de l'indicateur, les champs absents gardant leur valeur.
  AdminFeatureFlag copyWith({
    bool? isEnabled,
    String? description,
    DateTime? updatedAt,
    String? updatedBy,
  }) {
    return AdminFeatureFlag(
      key: key,
      isEnabled: isEnabled ?? this.isEnabled,
      description: description ?? this.description,
      updatedAt: updatedAt ?? this.updatedAt,
      updatedBy: updatedBy ?? this.updatedBy,
    );
  }
}

/// Le port du back-office.
///
/// L'écran lit ce port et n'atteint jamais le serveur. La doublure par
/// défaut refuse la lecture : tant que le point de composition n'a pas câblé
/// l'implémentation de la couche données, l'écran ne montre aucun compte
/// et aucun indicateur — il ne les invente pas.
abstract interface class AdminRepository {
  /// Les comptes du service, avec leur formule et leur usage.
  ///
  /// Le serveur rend la première page des comptes : la liste est celle que
  /// l'API connaît, elle ne prétend pas être celle des personnes qui se
  /// sont inscrites.
  Future<List<AdminAccount>> accounts();

  /// Le compte [userId], avec sa formule et son usage.
  ///
  /// Le serveur refuse la lecture quand il ne connaît pas ce compte.
  Future<AdminAccount> account(String userId);

  /// Les indicateurs de fonctionnalité du service.
  Future<List<AdminFeatureFlag>> featureFlags();

  /// Active ou désactive l'indicateur [key] et rend son nouvel état.
  ///
  /// Le serveur trace le changement dans son journal d'audit : allumer ou
  /// éteindre une fonctionnalité est une action sensible.
  Future<AdminFeatureFlag> setFeatureFlag(
    String key, {
    required bool isEnabled,
  });
}

/// Le dépôt du back-office.
///
/// Le point de composition le remplace par l'implémentation de la couche
/// données — l'implémentation qui parle à l'API, ou la doublure qui refuse
/// quand l'API n'est pas configurée sur ce poste. Le défaut refuse la
/// lecture : un écran ne présente jamais un compte qu'il n'a pas lu.
final Provider<AdminRepository> adminRepositoryProvider =
    Provider<AdminRepository>((Ref ref) {
      throw UnimplementedError(
        'The admin repository is not wired: override '
        '`adminRepositoryProvider` with the implementation of the data '
        'layer.',
      );
    });
