import 'book_sale_store.dart';

/// L'implémentation en mémoire du port [BookSaleStore].
///
/// Elle respecte les mêmes invariants que les implémentations SQL : un
/// livre a un prix, et les ventes du compte sont triées de la plus récente
/// à la plus ancienne.
final class InMemoryBookSaleStore implements BookSaleStore {
  /// Crée un port vide.
  InMemoryBookSaleStore();

  final Map<String, BookSaleRecord> _sales = <String, BookSaleRecord>{};

  @override
  Future<BookSaleRecord?> findByProject(String projectId) async =>
      _sales[projectId];

  @override
  Future<void> save(BookSaleRecord record) async {
    _sales[record.projectId] = record;
  }

  @override
  Future<List<BookSaleRecord>> listByOwner(String ownerId) async {
    final List<BookSaleRecord> owned = _sales.values
        .where((BookSaleRecord sale) => sale.ownerId == ownerId)
        .toList(growable: false);
    final List<BookSaleRecord> sorted = List<BookSaleRecord>.of(owned)
      ..sort((BookSaleRecord left, BookSaleRecord right) {
        final int byDate = right.updatedAt.compareTo(left.updatedAt);
        if (byDate != 0) return byDate;
        return left.projectId.compareTo(right.projectId);
      });
    return List<BookSaleRecord>.unmodifiable(sorted);
  }
}
