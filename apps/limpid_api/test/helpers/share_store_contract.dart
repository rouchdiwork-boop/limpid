import 'package:limpid_api/src/db/share_store.dart';
import 'package:test/test.dart';

/// Les partages sous test.
final class ShareFixture {
  /// Crée un cas.
  const ShareFixture({required this.shares, required this.dispose});

  /// Le magasin des partages.
  final ShareStore shares;

  /// Libère les ressources du cas.
  final Future<void> Function() dispose;
}

/// Exécute le contrat du port [ShareStore].
///
/// Les mêmes scénarios tournent contre le magasin en mémoire et contre le
/// magasin SQLite : l'égalité des deux exécutions est la preuve que la base
/// de développement se comporte comme l'implémentation de référence.
void runShareStoreContract({
  required String name,
  required Future<ShareFixture> Function() build,
}) {
  group('contrat des partages — $name', () {
    late ShareFixture fixture;

    setUp(() async {
      fixture = await build();
    });

    tearDown(() async {
      await fixture.dispose();
    });

    test('enregistre un partage et le relit', () async {
      await fixture.shares.insert(_share('share-1'));

      final ShareRecord? stored = await fixture.shares.findById('share-1');

      expect(stored, isNotNull);
      expect(stored!.projectId, 'project-1');
      expect(stored.ownerId, 'user-1');
      expect(stored.tokenHash, 'hash-share-1');
      expect(stored.isRevoked, isFalse);
      expect(stored.revokedAt, isNull);
      expect(stored.expiresAt, _expiry);
      expect(stored.createdAt, _moment);
    });

    test('ne rend pas un partage inconnu', () async {
      expect(await fixture.shares.findById('share-absent'), isNull);
    });

    test('liste les partages du compte, les plus récents d\'abord', () async {
      await fixture.shares.insert(_share('share-1', createdAt: _moment));
      await fixture.shares.insert(
        _share('share-2', createdAt: _moment.add(const Duration(hours: 1))),
      );
      await fixture.shares.insert(
        _share('share-3', ownerId: 'user-2', createdAt: _moment),
      );

      final SharePage page = await fixture.shares.listByOwner(
        userId: 'user-1',
        limit: 10,
      );

      expect(page.total, 2);
      expect(page.items.map((ShareRecord share) => share.id), <String>[
        'share-2',
        'share-1',
      ]);
    });

    test('ne montre pas les partages d\'un autre compte', () async {
      await fixture.shares.insert(_share('share-1', ownerId: 'user-2'));

      final SharePage page = await fixture.shares.listByOwner(
        userId: 'user-1',
        limit: 10,
      );

      expect(page.total, 0);
      expect(page.items, isEmpty);
    });

    test('pagine la liste avec un curseur', () async {
      await fixture.shares.insert(_share('share-1', createdAt: _moment));
      await fixture.shares.insert(
        _share('share-2', createdAt: _moment.add(const Duration(hours: 1))),
      );
      await fixture.shares.insert(
        _share('share-3', createdAt: _moment.add(const Duration(hours: 2))),
      );

      final SharePage first = await fixture.shares.listByOwner(
        userId: 'user-1',
        limit: 2,
      );
      expect(first.items, hasLength(2));
      expect(first.total, 3);
      expect(first.nextCursor, isNotNull);

      final SharePage second = await fixture.shares.listByOwner(
        userId: 'user-1',
        limit: 2,
        cursor: first.nextCursor,
      );
      expect(second.items.map((ShareRecord share) => share.id), <String>[
        'share-1',
      ]);
      expect(second.nextCursor, isNull);
    });

    test('met à jour un partage', () async {
      await fixture.shares.insert(_share('share-1'));

      await fixture.shares.update(
        _share('share-1').copyWith(
          isRevoked: true,
          revokedAt: _moment.add(const Duration(hours: 1)),
        ),
      );

      final ShareRecord? stored = await fixture.shares.findById('share-1');
      expect(stored!.isRevoked, isTrue);
      expect(stored.revokedAt, _moment.add(const Duration(hours: 1)));
    });
  });
}

/// L'instant de référence des partsages de la suite.
final DateTime _moment = DateTime.utc(2026, 10, 26, 9);

/// L'échéance des partages de la suite.
final DateTime _expiry = DateTime.utc(2026, 11, 2, 9);

/// Un partage de la suite.
ShareRecord _share(
  String id, {
  String ownerId = 'user-1',
  DateTime? createdAt,
}) {
  return ShareRecord(
    id: id,
    projectId: 'project-1',
    ownerId: ownerId,
    tokenHash: 'hash-$id',
    expiresAt: _expiry,
    isRevoked: false,
    createdAt: createdAt ?? _moment,
  );
}
