import '../http/pagination.dart';
import 'webhook_database.dart';
import 'webhook_record.dart';

/// L'implémentation en mémoire du port [WebhookDatabase].
///
/// Le port garde les mêmes invariants que les implémentations SQL : une clé
/// révoquée ne sert plus, une rotation remplace l'empreinte sans changer
/// l'identité, et le journal des livraisons ne perd aucune trace.
final class InMemoryWebhookDatabase implements WebhookDatabase {
  /// Crée un port vide.
  InMemoryWebhookDatabase();

  /// Les clés d'API, par identifiant.
  final Map<String, ApiKeyRecord> _keys = <String, ApiKeyRecord>{};

  /// Les points de rappel, par identifiant.
  final Map<String, WebhookEndpointRecord> _endpoints =
      <String, WebhookEndpointRecord>{};

  /// Les livraisons, par identifiant.
  final Map<String, WebhookDeliveryRecord> _deliveries =
      <String, WebhookDeliveryRecord>{};

  @override
  Future<ApiKeyRecord?> findApiKey(String id) async => _keys[id];

  @override
  Future<ApiKeyRecord?> findApiKeyByHash(String keyHash) async {
    for (final ApiKeyRecord record in _keys.values) {
      if (record.keyHash == keyHash) return record;
    }
    return null;
  }

  @override
  Future<WebhookPage<ApiKeyRecord>> listApiKeys({
    required String userId,
    required int limit,
    String? cursor,
  }) async {
    final List<ApiKeyRecord> owned = _keys.values
        .where((ApiKeyRecord record) => record.userId == userId)
        .toList(growable: false);
    return _page<ApiKeyRecord>(owned, limit, cursor, _sortKeyOfKey);
  }

  @override
  Future<void> insertApiKey(ApiKeyRecord record) async {
    _keys[record.id] = record;
  }

  @override
  Future<void> updateApiKey(ApiKeyRecord record) async {
    _keys[record.id] = record;
  }

  @override
  Future<void> deleteApiKey(String id) async {
    _keys.remove(id);
  }

  @override
  Future<WebhookEndpointRecord?> findEndpoint(String id) async =>
      _endpoints[id];

  @override
  Future<WebhookPage<WebhookEndpointRecord>> listEndpoints({
    required String userId,
    required int limit,
    String? cursor,
  }) async {
    final List<WebhookEndpointRecord> owned = _endpoints.values
        .where((WebhookEndpointRecord record) => record.userId == userId)
        .toList(growable: false);
    return _page<WebhookEndpointRecord>(
      owned,
      limit,
      cursor,
      _sortKeyOfEndpoint,
    );
  }

  @override
  Future<List<WebhookEndpointRecord>> listSubscribedEndpoints({
    required String userId,
    required String event,
  }) async {
    return _endpoints.values
        .where(
          (WebhookEndpointRecord endpoint) =>
              endpoint.userId == userId &&
              endpoint.isActive &&
              endpoint.events.contains(event),
        )
        .toList(growable: false);
  }

  @override
  Future<void> insertEndpoint(WebhookEndpointRecord endpoint) async {
    _endpoints[endpoint.id] = endpoint;
  }

  @override
  Future<void> updateEndpoint(WebhookEndpointRecord endpoint) async {
    _endpoints[endpoint.id] = endpoint;
  }

  @override
  Future<void> deleteEndpoint(String id) async {
    _endpoints.remove(id);
  }

  @override
  Future<WebhookDeliveryRecord?> findDelivery(String id) async =>
      _deliveries[id];

  @override
  Future<WebhookPage<WebhookDeliveryRecord>> listDeliveries({
    required String userId,
    required int limit,
    String? cursor,
  }) async {
    final List<WebhookDeliveryRecord> owned = _deliveries.values
        .where((WebhookDeliveryRecord record) => record.userId == userId)
        .toList(growable: false);
    return _page<WebhookDeliveryRecord>(
      owned,
      limit,
      cursor,
      _sortKeyOfDelivery,
    );
  }

  @override
  Future<void> insertDelivery(WebhookDeliveryRecord delivery) async {
    _deliveries[delivery.id] = delivery;
  }

  @override
  Future<void> updateDelivery(WebhookDeliveryRecord delivery) async {
    _deliveries[delivery.id] = delivery;
  }

  /// Trie les éléments comme le fait SQL, puis découpe la page demandée.
  ///
  /// Le tri est `created_at` décroissant puis `id` croissant : il est stable
  /// et le curseur s'appuie sur le même couple.
  static WebhookPage<T> _page<T>(
    List<T> records,
    int limit,
    String? cursor,
    DateTime Function(T record) createdAtOf,
  ) {
    final List<T> sorted = List<T>.of(records)
      ..sort((T left, T right) {
        final int byDate = createdAtOf(right).compareTo(createdAtOf(left));
        if (byDate != 0) return byDate;
        return _idOf(left).compareTo(_idOf(right));
      });

    final PageCursorValue? decoded = PageCursor.decode(cursor);
    final List<T> after = decoded == null
        ? sorted
        : sorted
              .where((T record) {
                final DateTime createdAt = createdAtOf(record);
                final DateTime boundary = DateTime.parse(
                  decoded.updatedAt,
                ).toUtc();
                if (createdAt.isBefore(boundary)) return true;
                if (createdAt.isAfter(boundary)) return false;
                return _idOf(record).compareTo(decoded.id) > 0;
              })
              .toList(growable: false);

    final bool hasMore = after.length > limit;
    final List<T> items = hasMore ? after.sublist(0, limit) : after;
    return WebhookPage<T>(
      items: List<T>.unmodifiable(items),
      total: sorted.length,
      nextCursor: hasMore && items.isNotEmpty
          ? PageCursor.encode(
              createdAtOf(items.last).toUtc().toIso8601String(),
              _idOf(items.last),
            )
          : null,
    );
  }

  static String _idOf<T>(T record) {
    if (record is ApiKeyRecord) return record.id;
    if (record is WebhookEndpointRecord) return record.id;
    if (record is WebhookDeliveryRecord) return record.id;
    throw ArgumentError.value(record, 'record', 'Type de registre inconnu.');
  }

  static DateTime _sortKeyOfKey(ApiKeyRecord record) => record.createdAt;

  static DateTime _sortKeyOfEndpoint(WebhookEndpointRecord record) =>
      record.createdAt;

  static DateTime _sortKeyOfDelivery(WebhookDeliveryRecord record) =>
      record.createdAt;
}
