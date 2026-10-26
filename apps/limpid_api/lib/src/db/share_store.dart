/// Le partage en lecture d'un projet.
///
/// Un partage relie trois choses : le projet partagé, le compte qui l'a
/// partagé, et un jeton secret que le lecteur possède. Le jeton n'est
/// jamais stocké en clair : la base n'en garde que l'empreinte, exactement
/// comme elle fait des clés d'API.
///
/// Un partage n'accorde **aucun droit d'écriture** : il ouvre le document,
/// rien d'autre.
final class ShareRecord {
  /// Crée un partage.
  const ShareRecord({
    required this.id,
    required this.projectId,
    required this.ownerId,
    required this.tokenHash,
    required this.expiresAt,
    required this.isRevoked,
    required this.createdAt,
    this.revokedAt,
  });

  /// L'identifiant du partage.
  final String id;

  /// Le projet partagé.
  final String projectId;

  /// Le compte qui a partagé le projet.
  final String ownerId;

  /// L'empreinte du jeton : le jeton lui-même n'est jamais stocké.
  final String tokenHash;

  /// L'instant d'expiration du partage.
  final DateTime expiresAt;

  /// Indique si le partage a été révoqué.
  final bool isRevoked;

  /// L'instant de la création.
  final DateTime createdAt;

  /// L'instant de la révocation, `null` quand le partage est vivant.
  final DateTime? revokedAt;

  /// Indique si le partage a expiré à l'instant [now].
  ///
  /// L'échéance est inclusive : à l'instant exact de l'échéance, le
  /// partage a expiré.
  bool isExpiredAt(DateTime now) => !now.toUtc().isBefore(expiresAt.toUtc());

  /// Indique si le partage ouvre encore le document à l'instant [now].
  ///
  /// Un partage révoqué ou expiré est mort : il répond comme un partage qui
  /// n'a jamais existé.
  bool isLiveAt(DateTime now) => !isRevoked && !isExpiredAt(now);

  /// Renvoie une copie du partage avec les champs remplacés.
  ///
  /// La révocation est irréversible : [revokedAt] ne peut pas être effacé
  /// par cette méthode.
  ShareRecord copyWith({bool? isRevoked, DateTime? revokedAt}) {
    return ShareRecord(
      id: id,
      projectId: projectId,
      ownerId: ownerId,
      tokenHash: tokenHash,
      expiresAt: expiresAt,
      isRevoked: isRevoked ?? this.isRevoked,
      createdAt: createdAt,
      revokedAt: revokedAt ?? this.revokedAt,
    );
  }

  /// La représentation JSON envoyée aux clients.
  ///
  /// L'empreinte du jeton n'y figure jamais : la liste des partages et la
  /// trace d'audit doivent pouvoir être montrées sans rien divulguer du
  /// secret.
  Map<String, Object?> toJson() {
    return <String, Object?>{
      'id': id,
      'project_id': projectId,
      'expires_at': expiresAt.toUtc().toIso8601String(),
      'is_revoked': isRevoked,
      'created_at': createdAt.toUtc().toIso8601String(),
      'revoked_at': revokedAt?.toUtc().toIso8601String(),
    };
  }
}

/// Une page de partages.
///
/// Le curseur est opaque : il encode la clé de tri du dernier élément de la
/// page, pour que le client n'ait pas à connaître l'ordre du tri.
final class SharePage {
  /// Crée une page.
  const SharePage({
    required this.items,
    required this.total,
    required this.nextCursor,
  });

  /// Les partages de la page.
  final List<ShareRecord> items;

  /// Le nombre total de partages du compte.
  final int total;

  /// Le curseur pointant sur la page suivante, `null` quand la page est la
  /// dernière.
  final String? nextCursor;
}

/// Le port de persistance des partages en lecture.
///
/// Le port ne porte aucune règle métier : l'échéance, la révocation et la
/// lecture du jeton vivent dans le service.
abstract interface class ShareStore {
  /// Le partage [id], `null` quand il n'existe pas.
  Future<ShareRecord?> findById(String id);

  /// Les partages du compte [userId], les plus récents d'abord.
  ///
  /// La liste est triée par `created_at` décroissant puis par `id`
  /// croissant : l'ordre est stable et le curseur de pagination s'appuie sur
  /// ce même tri.
  Future<SharePage> listByOwner({
    required String userId,
    required int limit,
    String? cursor,
  });

  /// Enregistre un nouveau partage.
  Future<void> insert(ShareRecord record);

  /// Met à jour un partage existant.
  Future<void> update(ShareRecord record);
}
