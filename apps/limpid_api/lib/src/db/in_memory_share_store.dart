import '../http/pagination.dart';
import 'share_store.dart';

/// L'implémentation en mémoire du port [ShareStore].
///
/// Le port garde les mêmes invariants que les implémentations SQL : le jeton
/// n'est jamais stocké en clair, la liste est triée comme la liste SQL, et
/// la révocation ne perd jamais la trace du partage.
final class InMemoryShareStore implements ShareStore {
  /// Crée un port vide.
  InMemoryShareStore();

  /// Les partages, par identifiant.
  final Map<String, ShareRecord> _shares = <String, ShareRecord>{};

  @override
  Future<ShareRecord?> findById(String id) async => _shares[id];

  @override
  Future<SharePage> listByOwner({
    required String userId,
    required int limit,
    String? cursor,
  }) async {
    final List<ShareRecord> owned = _shares.values
        .where((ShareRecord share) => share.ownerId == userId)
        .toList(growable: false);
    final List<ShareRecord> sorted = List<ShareRecord>.of(owned)
      ..sort((ShareRecord left, ShareRecord right) {
        final int byDate = right.createdAt.compareTo(left.createdAt);
        if (byDate != 0) return byDate;
        return left.id.compareTo(right.id);
      });

    final PageCursorValue? decoded = PageCursor.decode(cursor);
    final List<ShareRecord> after = decoded == null
        ? sorted
        : sorted
              .where((ShareRecord share) {
                final DateTime createdAt = share.createdAt.toUtc();
                final DateTime boundary = DateTime.parse(
                  decoded.updatedAt,
                ).toUtc();
                if (createdAt.isBefore(boundary)) return true;
                if (createdAt.isAfter(boundary)) return false;
                return share.id.compareTo(decoded.id) > 0;
              })
              .toList(growable: false);

    final bool hasMore = after.length > limit;
    final List<ShareRecord> items = hasMore ? after.sublist(0, limit) : after;
    return SharePage(
      items: List<ShareRecord>.unmodifiable(items),
      total: sorted.length,
      nextCursor: hasMore && items.isNotEmpty
          ? PageCursor.encode(
              items.last.createdAt.toUtc().toIso8601String(),
              items.last.id,
            )
          : null,
    );
  }

  @override
  Future<void> insert(ShareRecord record) async {
    _shares[record.id] = record;
  }

  @override
  Future<void> update(ShareRecord record) async {
    _shares[record.id] = record;
  }
}
