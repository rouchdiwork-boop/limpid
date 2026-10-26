import 'entitlement_store.dart';

/// L'implémentation en mémoire du port [EntitlementStore].
///
/// Elle respecte le même invariant que les implémentations SQL : un droit
/// est unique par acheteur et par livre, et un octroi déjà fait n'est pas
/// refait.
final class InMemoryEntitlementStore implements EntitlementStore {
  /// Crée un port vide.
  InMemoryEntitlementStore();

  final Map<String, EntitlementRecord> _byId = <String, EntitlementRecord>{};

  @override
  Future<EntitlementRecord?> find({
    required String userId,
    required String projectId,
  }) async {
    for (final EntitlementRecord record in _byId.values) {
      if (record.userId == userId && record.projectId == projectId) {
        return record;
      }
    }
    return null;
  }

  @override
  Future<EntitlementRecord?> findBySource(String source) async {
    for (final EntitlementRecord record in _byId.values) {
      if (record.source == source) return record;
    }
    return null;
  }

  @override
  Future<EntitlementGrant> grant(EntitlementRecord record) async {
    final EntitlementRecord? existing = await find(
      userId: record.userId,
      projectId: record.projectId,
    );
    if (existing != null) {
      return EntitlementGrant(record: existing, isNew: false);
    }
    final EntitlementRecord? bySource = await findBySource(record.source);
    if (bySource != null) {
      return EntitlementGrant(record: bySource, isNew: false);
    }
    _byId[record.id] = record;
    return EntitlementGrant(record: record, isNew: true);
  }

  @override
  Future<List<EntitlementRecord>> listByUser(String userId) async {
    final List<EntitlementRecord> owned = _byId.values
        .where((EntitlementRecord record) => record.userId == userId)
        .toList(growable: false);
    final List<EntitlementRecord> sorted = List<EntitlementRecord>.of(owned)
      ..sort((EntitlementRecord left, EntitlementRecord right) {
        final int byDate = right.grantedAt.compareTo(left.grantedAt);
        if (byDate != 0) return byDate;
        return left.id.compareTo(right.id);
      });
    return List<EntitlementRecord>.unmodifiable(sorted);
  }
}
