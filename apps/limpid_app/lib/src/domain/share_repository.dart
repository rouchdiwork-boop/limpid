/// Les partages en lecture des livres de l'auteur.
///
/// Le contrat vit dans la couche domaine : les écrans le nomment,
/// l'implémentation de la couche données le réalise — aucun des deux ne
/// connaît l'autre. Les types qu'il manipule sont **immuables** : l'écran
/// lit un état, il ne le modifie jamais.
///
/// Le jeton d'un partage est **rendu une seule fois** : le serveur ne le
/// rend plus jamais. L'écran le montre, il ne le garde pas.
///
/// Un partage n'accorde aucun droit d'écriture : il ouvre le document à
/// un lecteur qui n'a pas de compte, il n'ouvre rien à l'auteur.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:limpid_app/src/domain/providers.dart';

/// Un partage en lecture d'un livre.
///
/// Le jeton n'y figure jamais : la base du serveur n'en garde que
/// l'empreinte. L'écran ne connaît que le livre partagé, l'échéance et
/// l'état.
final class Share {
  /// Crée un partage.
  const Share({
    required this.id,
    required this.projectId,
    required this.expiresAt,
    required this.isRevoked,
    required this.createdAt,
    this.revokedAt,
  });

  /// L'identifiant du partage.
  final String id;

  /// Le livre partagé.
  final String projectId;

  /// L'instant d'expiration du partage.
  final DateTime expiresAt;

  /// Indique si le partage a été révoqué.
  final bool isRevoked;

  /// L'instant de la création.
  final DateTime createdAt;

  /// L'instant de la révocation, `null` quand le partage est vivant.
  final DateTime? revokedAt;

  /// Indique si le partage ouvre encore le livre.
  bool get isLive => !isRevoked;
}

/// Un partage et son jeton, au moment de la création.
///
/// Le jeton n'existe que dans cette réponse : l'application le montre une
/// fois, elle ne le garde pas.
final class CreatedShare {
  /// Crée un résultat.
  const CreatedShare({required this.share, required this.token});

  /// Le partage, tel que le serveur l'a enregistré.
  final Share share;

  /// Le jeton du partage, à montrer une seule fois.
  final String token;
}

/// Le port des partages en lecture.
///
/// L'écran lit ce port et n'atteint jamais le serveur. La doublure par
/// défaut refuse les appels et dit pourquoi : un écran ne présente jamais
/// un partage qu'il n'a pas lu.
abstract interface class ShareRepository {
  /// Les partages du compte.
  ///
  /// Le jeton n'y figure jamais : il n'est rendu qu'à la création.
  Future<List<Share>> shares();

  /// Partage le livre [projectId] et rend son jeton, **une seule fois**.
  ///
  /// [expiresInHours] est la durée de vie du partage ; le serveur applique
  /// sa durée par défaut quand elle est absente.
  Future<CreatedShare> createShare({
    required String projectId,
    int? expiresInHours,
  });

  /// Révoque le partage [shareId].
  ///
  /// Un partage révoqué n'ouvre plus rien : le lien répond une erreur
  /// comme un lien qui n'a jamais existé.
  Future<Share> revokeShare(String shareId);
}

/// Un [ShareRepository] qui ne peut pas atteindre le serveur.
///
/// Le mode démonstration n'a pas de service distant : l'écran le dit au
/// lieu de montrer une liste vide qui ferait croire que le compte n'a rien.
final class UnavailableShareRepository
    implements ShareRepository, UnavailableService {
  /// Crée le dépôt indisponible.
  const UnavailableShareRepository();

  @override
  Future<List<Share>> shares() async =>
      throw const ServiceUnavailableException();

  @override
  Future<CreatedShare> createShare({
    required String projectId,
    int? expiresInHours,
  }) async => throw const ServiceUnavailableException();

  @override
  Future<Share> revokeShare(String shareId) async =>
      throw const ServiceUnavailableException();
}

/// Le dépôt des partages en lecture.
///
/// Le point de composition le remplace par l'implémentation de la couche
/// données. Le défaut refuse les appels et dit pourquoi : un écran ne
/// présente jamais un partage qu'il n'a pas lu.
final Provider<ShareRepository> shareRepositoryProvider =
    Provider<ShareRepository>((Ref ref) => const UnavailableShareRepository());
