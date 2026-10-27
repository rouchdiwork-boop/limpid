import 'package:limpid_api/src/db/bundle_record.dart';
import 'package:limpid_api/src/db/in_memory_bundle_store.dart';
import 'package:limpid_api/src/db/sqlite_bundle_store.dart';
import 'package:limpid_api/src/db/sqlite_database.dart';
import 'package:limpid_api/src/db/sqlite_migration_runner.dart';
import 'package:test/test.dart';

import 'helpers/store_fixture.dart';

void main() {
  for (final MapEntry<String, Future<_Fixture> Function()> entry
      in <String, Future<_Fixture> Function()>{
        'mémoire': _inMemoryFixture,
        'SQLite': _sqliteFixture,
      }.entries) {
    group('contrat des bundles — ${entry.key}', () {
      late _Fixture fixture;

      setUp(() async {
        fixture = await entry.value();
      });

      tearDown(() async {
        await fixture.dispose();
      });

      test('un bundle absent n\'existe pas', () async {
        expect(await fixture.store.findById('bundle-1'), isNull);
      });

      test('le bundle est relu', () async {
        await fixture.store.save(_bundle());

        final BundleRecord? found = await fixture.store.findById('bundle-1');

        expect(found, isNotNull);
        expect(found!.id, 'bundle-1');
        expect(found.ownerId, 'auteur-1');
        expect(found.title, 'Les deux livres');
        expect(found.description, 'Un ensemble.');
        expect(found.projectIds, <String>['projet-1', 'projet-2']);
        expect(found.priceInCents, 1500);
        expect(found.currency, 'eur');
        expect(found.isPublished, isTrue);
        expect(found.isFree, isFalse);
      });

      test('l\'ordre des livres est conserve', () async {
        await fixture.store.save(
          _bundle(projectIds: <String>['projet-3', 'projet-1', 'projet-2']),
        );

        final BundleRecord? found = await fixture.store.findById('bundle-1');

        expect(found!.projectIds, <String>['projet-3', 'projet-1', 'projet-2']);
      });

      test(
        'un bundle a un seul prix : l\'ecriture remplace la precedente',
        () async {
          await fixture.store.save(_bundle());
          await fixture.store.save(
            _bundle(priceInCents: 900, isPublished: false),
          );

          final BundleRecord? found = await fixture.store.findById('bundle-1');

          expect(found!.priceInCents, 900);
          expect(found.isPublished, isFalse);
        },
      );

      test(
        'les bundles du compte sont tries du plus recent au plus ancien',
        () async {
          await fixture.store.save(
            _bundle(id: 'bundle-1', createdAt: DateTime.utc(2026, 1, 1)),
          );
          await fixture.store.save(
            _bundle(id: 'bundle-2', createdAt: DateTime.utc(2026, 2, 1)),
          );
          await fixture.store.save(
            _bundle(
              id: 'bundle-3',
              ownerId: 'auteur-2',
              createdAt: DateTime.utc(2026, 3, 1),
            ),
          );

          final List<BundleRecord> owned = await fixture.store.listByOwner(
            'auteur-1',
          );

          expect(owned, hasLength(2));
          expect(owned.first.id, 'bundle-2');
          expect(owned.last.id, 'bundle-1');
        },
      );
    });
  }
}

/// Le magasin sous test, et les ressources qu'il porte.
final class _Fixture {
  const _Fixture({required this.store, required this.dispose});

  final BundleStore store;
  final Future<void> Function() dispose;
}

/// Le magasin en mémoire.
Future<_Fixture> _inMemoryFixture() async {
  return _Fixture(store: InMemoryBundleStore(), dispose: () async {});
}

/// Le magasin SQLite.
Future<_Fixture> _sqliteFixture() async {
  final SqliteDatabase database = await SqliteDatabase.openInMemory();
  await SqliteMigrationRunner(
    database: database,
    directory: sqliteMigrationsDirectory,
  ).run();
  return _Fixture(store: SqliteBundleStore(database), dispose: database.close);
}

/// Un bundle.
BundleRecord _bundle({
  String id = 'bundle-1',
  String ownerId = 'auteur-1',
  List<String>? projectIds,
  int priceInCents = 1500,
  bool isPublished = true,
  DateTime? createdAt,
}) {
  final DateTime moment = createdAt ?? DateTime.utc(2026, 1, 1);
  return BundleRecord(
    id: id,
    ownerId: ownerId,
    title: 'Les deux livres',
    description: 'Un ensemble.',
    projectIds: projectIds ?? <String>['projet-1', 'projet-2'],
    priceInCents: priceInCents,
    currency: 'eur',
    isPublished: isPublished,
    createdAt: moment,
  );
}
