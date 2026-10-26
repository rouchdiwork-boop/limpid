/// Le marqueur d'une valeur absente dans les méthodes `copyWith`.
///
/// Les champs facultatifs doivent pouvoir être remis à `null` : sans ce
/// marqueur, `copyWith` ne saurait pas distinguer « ne change rien » de
/// « efface ».
const Object _absent = Object();

/// La valeur du champ [value], ou [fallback] quand le champ est absent.
T? _or<T>(Object? value, T? fallback) {
  if (identical(value, _absent)) return fallback;
  return value as T?;
}

/// Le statut d'une tentative de livraison d'un webhook.
///
/// Les trois statuts sont ceux de la table `webhook_deliveries` : une
/// livraison est en cours, elle a abouti, ou elle a échoué.
enum WebhookDeliveryStatus {
  /// La livraison a étéPreparée mais son issue n'est pas encore connue.
  pending('pending'),

  /// Le point de rappel a répondu avec un code de succès.
  succeeded('succeeded'),

  /// Le point de rappel a répondu avec un code d'erreur, ou n'a pas répondu.
  failed('failed');

  /// Crée un statut.
  const WebhookDeliveryStatus(this.key);

  /// Le nom technique du statut, stable dans la base.
  final String key;

  /// Le statut portant le nom [raw], `null` quand le nom est inconnu.
  static WebhookDeliveryStatus? parse(String raw) {
    for (final WebhookDeliveryStatus status in WebhookDeliveryStatus.values) {
      if (status.key == raw) return status;
    }
    return null;
  }
}

/// Une clé d'API, telle que la base la stocke.
///
/// La clé n'est jamais stockée : la table ne porte que son empreinte
/// [keyHash]. Le secret montré à l'auteur n'existe que dans la réponse de la
/// création et de la rotation.
final class ApiKeyRecord {
  /// Crée un enregistrement.
  const ApiKeyRecord({
    required this.id,
    required this.userId,
    required this.name,
    required this.keyHash,
    required this.scopes,
    required this.isActive,
    required this.createdAt,
    this.rotatedAt,
    this.revokedAt,
    this.lastUsedAt,
  });

  /// L'identifiant de la clé.
  ///
  /// L'identifiant ne change jamais : une clé rottée garde son identité, donc
  /// les intégrations qui la référencent continuent de fonctionner.
  final String id;

  /// Le compte propriétaire de la clé.
  final String userId;

  /// Le nom donné à la clé, pour que l'auteur la retrouve dans sa liste.
  final String name;

  /// L'empreinte de la clé.
  ///
  /// L'empreinte est le SHA-256 de la clé complète, en hexadécimal.
  final String keyHash;

  /// Le périmètre de la clé.
  final Set<String> scopes;

  /// Indique si la clé est active.
  final bool isActive;

  /// L'instant de la création.
  final DateTime createdAt;

  /// L'instant de la dernière rotation, `null` quand la clé n'a jamais été
  /// rottée.
  final DateTime? rotatedAt;

  /// L'instant de la révocation, `null` quand la clé est vivante.
  final DateTime? revokedAt;

  /// L'instant du dernier usage, `null` quand la clé n'a jamais servi.
  final DateTime? lastUsedAt;

  /// Indique si la clé a été révoquée.
  bool get isRevoked => revokedAt != null;

  /// Indique si la clé peut servir à authentifier un appel.
  bool get isUsable => isActive && !isRevoked;

  /// Renvoie une copie de l'enregistrement avec les champs remplacés.
  ApiKeyRecord copyWith({
    String? name,
    String? keyHash,
    Set<String>? scopes,
    bool? isActive,
    Object? rotatedAt = _absent,
    Object? revokedAt = _absent,
    Object? lastUsedAt = _absent,
  }) {
    return ApiKeyRecord(
      id: id,
      userId: userId,
      name: name ?? this.name,
      keyHash: keyHash ?? this.keyHash,
      scopes: scopes ?? this.scopes,
      isActive: isActive ?? this.isActive,
      createdAt: createdAt,
      rotatedAt: _or(rotatedAt, this.rotatedAt),
      revokedAt: _or(revokedAt, this.revokedAt),
      lastUsedAt: _or(lastUsedAt, this.lastUsedAt),
    );
  }

  /// La représentation JSON envoyée aux clients.
  ///
  /// L'empreinte de la clé n'y figure jamais : elle ne quitte pas la base.
  Map<String, Object?> toJson() {
    return <String, Object?>{
      'id': id,
      'name': name,
      'scopes': scopes.toList(growable: false)..sort(),
      'is_active': isActive,
      'is_revoked': isRevoked,
      'created_at': createdAt.toUtc().toIso8601String(),
      'rotated_at': rotatedAt?.toUtc().toIso8601String(),
      'revoked_at': revokedAt?.toUtc().toIso8601String(),
      'last_used_at': lastUsedAt?.toUtc().toIso8601String(),
    };
  }
}

/// Un point de rappel des webhooks sortants.
///
/// Le point porte l'URL déclarée par le compte, la liste des événements
/// abonnés et le secret de signature. La rotation du secret conserve
/// l'ancien pendant une période de transition : les deux sont alors
/// acceptés par le destinataire.
final class WebhookEndpointRecord {
  /// Crée un enregistrement.
  const WebhookEndpointRecord({
    required this.id,
    required this.userId,
    required this.url,
    required this.events,
    required this.secret,
    required this.isActive,
    required this.createdAt,
    required this.updatedAt,
    this.previousSecret,
    this.previousSecretExpiresAt,
  });

  /// L'identifiant du point de rappel.
  final String id;

  /// Le compte propriétaire du point de rappel.
  final String userId;

  /// L'URL de rappel, absolue et en `https` hors développement.
  final String url;

  /// Les événements auxquels le point est abonné.
  final Set<String> events;

  /// Le secret de signature courant.
  final String secret;

  /// Le secret précédent, conservé pendant la période de transition.
  final String? previousSecret;

  /// L'instant où le secret précédent cesse d'être accepté.
  final DateTime? previousSecretExpiresAt;

  /// Indique si le point de rappel reçoit encore des livraisons.
  final bool isActive;

  /// L'instant de la création.
  final DateTime createdAt;

  /// L'instant de la dernière modification.
  final DateTime updatedAt;

  /// Indique si un secret précédent est encore accepté à l'instant [at].
  bool isPreviousSecretValid(DateTime at) {
    final String? secret = previousSecret;
    final DateTime? expiresAt = previousSecretExpiresAt;
    if (secret == null || expiresAt == null) return false;
    return at.toUtc().isBefore(expiresAt.toUtc());
  }

  /// Renvoie une copie de l'enregistrement avec les champs remplacés.
  WebhookEndpointRecord copyWith({
    String? url,
    Set<String>? events,
    String? secret,
    Object? previousSecret = _absent,
    Object? previousSecretExpiresAt = _absent,
    bool? isActive,
    DateTime? updatedAt,
  }) {
    return WebhookEndpointRecord(
      id: id,
      userId: userId,
      url: url ?? this.url,
      events: events ?? this.events,
      secret: secret ?? this.secret,
      previousSecret: _or(previousSecret, this.previousSecret),
      previousSecretExpiresAt: _or(
        previousSecretExpiresAt,
        this.previousSecretExpiresAt,
      ),
      isActive: isActive ?? this.isActive,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  /// La représentation JSON envoyée aux clients.
  ///
  /// Aucun secret ne figure dans cette représentation : le secret n'est
  /// renvoyé qu'à la création et à la rotation.
  Map<String, Object?> toJson() {
    return <String, Object?>{
      'id': id,
      'url': url,
      'events': events.toList(growable: false)..sort(),
      'is_active': isActive,
      'has_previous_secret': previousSecret != null,
      'previous_secret_expires_at': previousSecretExpiresAt
          ?.toUtc()
          .toIso8601String(),
      'created_at': createdAt.toUtc().toIso8601String(),
      'updated_at': updatedAt.toUtc().toIso8601String(),
    };
  }
}

/// La trace d'une tentative de livraison.
///
/// La trace est la preuve de la livraison : elle porte le statut, le code
/// HTTP répondu et l'instant. Elle conserve la charge envoyée, pour que la
/// livraison puisse être rejouée à la main.
final class WebhookDeliveryRecord {
  /// Crée un enregistrement.
  const WebhookDeliveryRecord({
    required this.id,
    required this.endpointId,
    required this.userId,
    required this.event,
    required this.payload,
    required this.status,
    required this.attempts,
    required this.createdAt,
    this.httpStatus,
    this.errorMessage,
    this.completedAt,
  });

  /// L'identifiant de la livraison.
  ///
  /// L'identifiant est celui de l'événement : un rejeu renvoie la même
  /// charge, donc le même identifiant, et le destinataire peut écarter le
  /// doublon.
  final String id;

  /// Le point de rappel qui a reçu la livraison.
  final String endpointId;

  /// Le compte propriétaire de la livraison.
  final String userId;

  /// L'événement livré.
  final String event;

  /// La charge JSON envoyée, telle qu'elle a été signée.
  final String payload;

  /// Le statut de la livraison.
  final WebhookDeliveryStatus status;

  /// Le code HTTP répondu par le point de rappel, `null` quand il n'a pas
  /// répondu.
  final int? httpStatus;

  /// Le motif de l'échec, `null` quand la livraison a abouti.
  final String? errorMessage;

  /// Le nombre de tentatives, replay compris.
  final int attempts;

  /// L'instant de la préparation de la livraison.
  final DateTime createdAt;

  /// L'instant où l'issue de la tentative a été connue.
  final DateTime? completedAt;

  /// Indique si la livraison a échoué.
  bool get isFailed => status == WebhookDeliveryStatus.failed;

  /// Renvoie une copie de l'enregistrement avec les champs remplacés.
  WebhookDeliveryRecord copyWith({
    WebhookDeliveryStatus? status,
    Object? httpStatus = _absent,
    Object? errorMessage = _absent,
    int? attempts,
    Object? completedAt = _absent,
  }) {
    return WebhookDeliveryRecord(
      id: id,
      endpointId: endpointId,
      userId: userId,
      event: event,
      payload: payload,
      status: status ?? this.status,
      httpStatus: _or(httpStatus, this.httpStatus),
      errorMessage: _or(errorMessage, this.errorMessage),
      attempts: attempts ?? this.attempts,
      createdAt: createdAt,
      completedAt: _or(completedAt, this.completedAt),
    );
  }

  /// La représentation JSON envoyée aux clients.
  ///
  /// La charge n'y figure que sur la lecture d'une livraison : une liste
  /// ne répète pas le contenu des événements.
  Map<String, Object?> toJson({bool includePayload = false}) {
    return <String, Object?>{
      'id': id,
      'endpoint_id': endpointId,
      'event': event,
      'status': status.key,
      'http_status': httpStatus,
      'error_message': errorMessage,
      'attempts': attempts,
      'created_at': createdAt.toUtc().toIso8601String(),
      'completed_at': completedAt?.toUtc().toIso8601String(),
      if (includePayload) 'payload': payload,
    };
  }
}
