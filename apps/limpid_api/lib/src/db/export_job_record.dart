/// L'état d'un travail d'export.
///
/// Le travail est un **événement** : il attend le worker (`queued`), le
/// worker produit l'artefact (`running`), et le travail finit en `succeeded`
/// ou en `failed`. Il ne revient jamais en arrière, et il n'est jamais
/// rejoué : une relance crée un travail **neuf**.
///
/// Un travail en échec ne consomme rien : la consommation n'est comptée
/// qu'au succès.
enum ExportJobStatus {
  /// Le travail attend le worker.
  queued('queued'),

  /// Le worker produit l'artefact du travail.
  running('running'),

  /// L'artefact est produit et rangé dans le stockage.
  succeeded('succeeded'),

  /// La production a échoué : le message porte la cause.
  failed('failed');

  const ExportJobStatus(this.key);

  /// Le nom technique de l'état, stable dans la base et dans le contrat.
  final String key;

  /// L'état de nom technique [key], `null` quand il est inconnu.
  ///
  /// Une ligne dont l'état est inconnu est une ligne corrompue : elle est
  /// lue comme un travail en échec, jamais comme un travail réussi.
  static ExportJobStatus? fromKey(String key) {
    for (final ExportJobStatus status in ExportJobStatus.values) {
      if (status.key == key) return status;
    }
    return null;
  }
}

/// Un travail d'export.
///
/// La ligne porte la demande de l'auteur (le compte, le livre, le format et
/// la couverture), l'état du travail et les instants de sa vie. L'artefact
/// produit est désigné par sa clé dans le stockage : le travail ne porte
/// jamais les octets du livre.
final class ExportJobRecord {
  /// Crée un travail.
  const ExportJobRecord({
    required this.id,
    required this.userId,
    required this.projectId,
    required this.format,
    required this.cover,
    required this.status,
    required this.createdAt,
    this.artifactKey,
    this.error,
    this.errorCode,
    this.startedAt,
    this.finishedAt,
    this.expiresAt,
  });

  /// L'identifiant du travail.
  final String id;

  /// Le compte qui a demandé le travail.
  final String userId;

  /// Le livre exporté.
  final String projectId;

  /// Le format demandé, sous son nom technique.
  final String format;

  /// La variante de couverture demandée, sous son nom technique.
  final String cover;

  /// L'état du travail.
  final ExportJobStatus status;

  /// La clé de l'artefact produit, `null` tant que le travail n'a pas
  /// réussi.
  final String? artifactKey;

  /// Le message de l'échec, `null` quand le travail n'a pas échoué.
  final String? error;

  /// Le code technique de l'échec, `null` quand le travail n'a pas
  /// échoué.
  ///
  /// Le code dit **pourquoi** le travail a échoué — un quota atteint, un
  /// livre sans contenu, un générateur en faute — sans dire comment : le
  /// message fait cela.
  final String? errorCode;

  /// L'instant de la demande.
  final DateTime createdAt;

  /// L'instant du début de la production, `null` tant que le worker n'a
  /// pas pris le travail.
  final DateTime? startedAt;

  /// L'instant de la fin, `null` tant que le travail n'est pas fini.
  final DateTime? finishedAt;

  /// L'instant où l'artefact expire, `null` tant que le travail n'a pas
  /// réussi.
  final DateTime? expiresAt;

  /// Le travail est-il fini, quelle qu'en soit l'issue.
  bool get isFinished =>
      status == ExportJobStatus.succeeded || status == ExportJobStatus.failed;

  /// L'artefact du travail a-t-il expiré à l'instant [now].
  ///
  /// Un travail sans artefact n'est jamais expiré : il n'a rien à perdre.
  bool isExpiredAt(DateTime now) {
    final DateTime? expiry = expiresAt;
    if (expiry == null) return false;
    return !now.isBefore(expiry);
  }

  /// Le travail en copie modifiée.
  ///
  /// Les champs absents gardent leur valeur : la copie est un nouvel objet,
  /// jamais le travail modifié sur place.
  ExportJobRecord copyWith({
    ExportJobStatus? status,
    String? artifactKey,
    String? error,
    String? errorCode,
    DateTime? startedAt,
    DateTime? finishedAt,
    DateTime? expiresAt,
  }) {
    return ExportJobRecord(
      id: id,
      userId: userId,
      projectId: projectId,
      format: format,
      cover: cover,
      status: status ?? this.status,
      createdAt: createdAt,
      artifactKey: artifactKey ?? this.artifactKey,
      error: error ?? this.error,
      errorCode: errorCode ?? this.errorCode,
      startedAt: startedAt ?? this.startedAt,
      finishedAt: finishedAt ?? this.finishedAt,
      expiresAt: expiresAt ?? this.expiresAt,
    );
  }

  /// La représentation JSON du travail.
  ///
  /// La charge porte l'identifiant, l'état, le livre, le format, le
  /// message d'échec et les instants : ni le texte du livre, ni le compte
  /// qui a demandé le travail.
  Map<String, Object?> toJson() {
    return <String, Object?>{
      'id': id,
      'status': status.key,
      'project_id': projectId,
      'format': format,
      'cover': cover,
      'error': error,
      'error_code': errorCode,
      'created_at': createdAt.toUtc().toIso8601String(),
      'started_at': startedAt?.toUtc().toIso8601String(),
      'finished_at': finishedAt?.toUtc().toIso8601String(),
      'expires_at': expiresAt?.toUtc().toIso8601String(),
    };
  }
}
