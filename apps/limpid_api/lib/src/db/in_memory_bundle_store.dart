import 'bundle_record.dart';

/// L'implémentation en mémoire du port [BundleStore].
///
/// Elle respecte les mêmes invariants que les implémentations SQL : un
/// bundle a un prix, et les bundles du compte sont triés du plus récent au
/// plus ancien.
final class InMemoryBundleStore implements BundleStore {
  /// Crée un port vide.
  InMemoryBundleStore();

  final Map<String, BundleRecord> _bundles = <String, BundleRecord>{};

  @override
  Future<BundleRecord?> findById(String bundleId) async => _bundles[bundleId];

  @override
  Future<void> save(BundleRecord record) async {
    _bundles[record.id] = record;
  }

  @override
  Future<List<BundleRecord>> listByOwner(String ownerId) async {
    final List<BundleRecord> owned = _bundles.values
        .where((BundleRecord bundle) => bundle.ownerId == ownerId)
        .toList(growable: false);
    final List<BundleRecord> sorted = List<BundleRecord>.of(owned)
      ..sort((BundleRecord left, BundleRecord right) {
        final int byDate = right.createdAt.compareTo(left.createdAt);
        if (byDate != 0) return byDate;
        return left.id.compareTo(right.id);
      });
    return List<BundleRecord>.unmodifiable(sorted);
  }
}
