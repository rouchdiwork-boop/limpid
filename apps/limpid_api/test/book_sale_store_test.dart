import 'package:limpid_api/src/db/book_sale_store.dart';
import 'package:limpid_api/src/db/entitlement_store.dart';
import 'package:limpid_api/src/db/in_memory_book_sale_store.dart';
import 'package:limpid_api/src/db/in_memory_entitlement_store.dart';
import 'package:limpid_api/src/db/in_memory_promo_code_store.dart';
import 'package:limpid_api/src/db/promo_code_store.dart';
import 'package:limpid_api/src/db/sqlite_book_sale_store.dart';
import 'package:limpid_api/src/db/sqlite_database.dart';
import 'package:limpid_api/src/db/sqlite_entitlement_store.dart';
import 'package:limpid_api/src/db/sqlite_migration_runner.dart';
import 'package:limpid_api/src/db/sqlite_promo_code_store.dart';
import 'package:test/test.dart';

import 'helpers/store_fixture.dart';

void main() {
  for (final MapEntry<String, Future<_Stores> Function()> entry
      in <String, Future<_Stores> Function()>{
        'mémoire': _inMemoryStores,
        'SQLite': _sqliteStores,
      }.entries) {
    group('contrat des ventes — ${entry.key}', () {
      late _Stores stores;

      setUp(() async {
        stores = await entry.value();
      });

      tearDown(() async {
        await stores.dispose();
      });

      test('un livre absent n\'a pas de vente', () async {
        expect(await stores.sales.findByProject('projet-1'), isNull);
      });

      test('la vente du livre est relue', () async {
        await stores.sales.save(_sale());

        final BookSaleRecord? found = await stores.sales.findByProject(
          'projet-1',
        );

        expect(found, isNotNull);
        expect(found!.projectId, 'projet-1');
        expect(found.ownerId, 'auteur-1');
        expect(found.title, 'Le livre');
        expect(found.priceInCents, 1200);
        expect(found.currency, 'eur');
        expect(found.status, BookSaleStatus.published);
        expect(found.authorShare, 9000);
        expect(found.platformShare, 1000);
      });

      test(
        'un livre a un seul prix : la vente remplace la precedente',
        () async {
          await stores.sales.save(_sale());
          await stores.sales.save(
            _sale(priceInCents: 900, status: BookSaleStatus.withdrawn),
          );

          final BookSaleRecord? found = await stores.sales.findByProject(
            'projet-1',
          );

          expect(found!.priceInCents, 900);
          expect(found.status, BookSaleStatus.withdrawn);
        },
      );

      test('les ventes du compte sont triees de la plus recente a la plus '
          'ancienne', () async {
        await stores.sales.save(
          _sale(projectId: 'projet-1', updatedAt: DateTime.utc(2026, 1, 1)),
        );
        await stores.sales.save(
          _sale(projectId: 'projet-2', updatedAt: DateTime.utc(2026, 2, 1)),
        );
        await stores.sales.save(
          _sale(
            projectId: 'projet-3',
            ownerId: 'auteur-2',
            updatedAt: DateTime.utc(2026, 3, 1),
          ),
        );

        final List<BookSaleRecord> owned = await stores.sales.listByOwner(
          'auteur-1',
        );

        expect(owned, hasLength(2));
        expect(owned.first.projectId, 'projet-2');
        expect(owned.last.projectId, 'projet-1');
      });
    });

    group('contrat des droits — ${entry.key}', () {
      late _Stores stores;

      setUp(() async {
        stores = await entry.value();
      });

      tearDown(() async {
        await stores.dispose();
      });

      test('un compte sans droit ne l\'a pas', () async {
        expect(
          await stores.entitlements.find(
            userId: 'acheteur-1',
            projectId: 'projet-1',
          ),
          isNull,
        );
      });

      test('le droit accorde porte la ventilation', () async {
        final EntitlementGrant grant = await stores.entitlements.grant(
          _entitlement(),
        );

        expect(grant.isNew, isTrue);
        expect(grant.record.amountInCents, 1200);
        expect(grant.record.authorAmountInCents, 1080);
        expect(grant.record.platformAmountInCents, 120);
        expect(grant.record.source, 'cs_test_1');
      });

      test('le meme paiement ne cree pas deux droits', () async {
        await stores.entitlements.grant(_entitlement());
        final EntitlementGrant second = await stores.entitlements.grant(
          _entitlement(id: 'droit-2', source: 'cs_test_2'),
        );

        expect(second.isNew, isFalse);
        expect(second.record.id, 'droit-1');
        final List<EntitlementRecord> owned = await stores.entitlements
            .listByUser('acheteur-1');
        expect(owned, hasLength(1));
      });

      test('la commande qui a paye le droit est relue', () async {
        await stores.entitlements.grant(_entitlement());

        final EntitlementRecord? found = await stores.entitlements.findBySource(
          'cs_test_1',
        );

        expect(found, isNotNull);
        expect(found!.projectId, 'projet-1');
      });

      test('les droits du compte sont tries de la plus recente a la plus '
          'ancienne', () async {
        await stores.entitlements.grant(
          _entitlement(
            id: 'droit-1',
            projectId: 'projet-1',
            source: 'cs_test_1',
            grantedAt: DateTime.utc(2026, 1, 1),
          ),
        );
        await stores.entitlements.grant(
          _entitlement(
            id: 'droit-2',
            projectId: 'projet-2',
            source: 'cs_test_2',
            grantedAt: DateTime.utc(2026, 2, 1),
          ),
        );
        await stores.entitlements.grant(
          _entitlement(
            id: 'droit-3',
            projectId: 'projet-3',
            source: 'cs_test_3',
            userId: 'acheteur-2',
            grantedAt: DateTime.utc(2026, 3, 1),
          ),
        );

        final List<EntitlementRecord> owned = await stores.entitlements
            .listByUser('acheteur-1');

        expect(owned, hasLength(2));
        expect(owned.first.projectId, 'projet-2');
        expect(owned.last.projectId, 'projet-1');
      });
    });

    group('contrat des codes promo — ${entry.key}', () {
      late _Stores stores;

      setUp(() async {
        stores = await entry.value();
      });

      tearDown(() async {
        await stores.dispose();
      });

      test('un code inconnu est refuse', () async {
        final PromoReservation reservation = await stores.promoCodes.reserve(
          code: 'INCONNU',
          userId: 'acheteur-1',
          at: DateTime.utc(2026, 1, 1),
        );

        expect(reservation, isA<PromoReservationRefused>());
        expect(
          (reservation as PromoReservationRefused).reason,
          PromoRefusalReason.unknown,
        );
      });

      test('un code expire est refuse', () async {
        await stores.promoCodes.save(
          _promoCode(expiresAt: DateTime.utc(2026, 1, 1)),
        );

        final PromoReservation reservation = await stores.promoCodes.reserve(
          code: 'BIENVENUE',
          userId: 'acheteur-1',
          at: DateTime.utc(2026, 2, 1),
        );

        expect(
          (reservation as PromoReservationRefused).reason,
          PromoRefusalReason.expired,
        );
      });

      test('un code epuise est refuse', () async {
        await stores.promoCodes.save(_promoCode(maxUses: 1));

        final PromoReservation first = await stores.promoCodes.reserve(
          code: 'BIENVENUE',
          userId: 'acheteur-1',
          at: DateTime.utc(2026, 1, 1),
        );
        final PromoReservation second = await stores.promoCodes.reserve(
          code: 'BIENVENUE',
          userId: 'acheteur-2',
          at: DateTime.utc(2026, 1, 1),
        );

        expect(first, isA<PromoReservationGranted>());
        expect(
          (second as PromoReservationRefused).reason,
          PromoRefusalReason.exhausted,
        );
      });

      test('un code deja utilise par ce compte est refuse', () async {
        await stores.promoCodes.save(_promoCode(maxUses: 10));

        await stores.promoCodes.reserve(
          code: 'BIENVENUE',
          userId: 'acheteur-1',
          at: DateTime.utc(2026, 1, 1),
        );
        final PromoReservation second = await stores.promoCodes.reserve(
          code: 'BIENVENUE',
          userId: 'acheteur-1',
          at: DateTime.utc(2026, 1, 1),
        );

        expect(
          (second as PromoReservationRefused).reason,
          PromoRefusalReason.alreadyUsed,
        );
      });

      test('le quota du code est decremente', () async {
        await stores.promoCodes.save(_promoCode(maxUses: 3));

        await stores.promoCodes.reserve(
          code: 'BIENVENUE',
          userId: 'acheteur-1',
          at: DateTime.utc(2026, 1, 1),
        );
        await stores.promoCodes.reserve(
          code: 'BIENVENUE',
          userId: 'acheteur-2',
          at: DateTime.utc(2026, 1, 1),
        );

        final PromoCodeRecord? code = await stores.promoCodes.findByCode(
          'bienvenue',
        );
        expect(code!.uses, 2);
      });

      test('le code se lit sans tenir compte de la casse', () async {
        await stores.promoCodes.save(_promoCode());

        expect(await stores.promoCodes.findByCode('  BIENVENUE '), isNotNull);
      });
    });
  }
}

/// Les magasins sous test.
final class _Stores {
  const _Stores({
    required this.sales,
    required this.entitlements,
    required this.promoCodes,
    required this.dispose,
  });

  final BookSaleStore sales;
  final EntitlementStore entitlements;
  final PromoCodeStore promoCodes;
  final Future<void> Function() dispose;
}

/// Les magasins en mémoire.
Future<_Stores> _inMemoryStores() async {
  return _Stores(
    sales: InMemoryBookSaleStore(),
    entitlements: InMemoryEntitlementStore(),
    promoCodes: InMemoryPromoCodeStore(),
    dispose: () async {},
  );
}

/// Les magasins SQLite.
Future<_Stores> _sqliteStores() async {
  final SqliteDatabase database = await SqliteDatabase.openInMemory();
  await SqliteMigrationRunner(
    database: database,
    directory: sqliteMigrationsDirectory,
  ).run();
  return _Stores(
    sales: SqliteBookSaleStore(database),
    entitlements: SqliteEntitlementStore(database),
    promoCodes: SqlitePromoCodeStore(database),
    dispose: database.close,
  );
}

/// Une vente de livre.
BookSaleRecord _sale({
  String projectId = 'projet-1',
  String ownerId = 'auteur-1',
  int priceInCents = 1200,
  BookSaleStatus status = BookSaleStatus.published,
  DateTime? updatedAt,
}) {
  final DateTime moment = updatedAt ?? DateTime.utc(2026, 1, 1);
  return BookSaleRecord(
    projectId: projectId,
    ownerId: ownerId,
    title: 'Le livre',
    priceInCents: priceInCents,
    currency: 'eur',
    status: status,
    authorShare: 9000,
    platformShare: 1000,
    createdAt: moment,
    updatedAt: moment,
    publishedAt: moment,
  );
}

/// Un droit de lecture.
EntitlementRecord _entitlement({
  String id = 'droit-1',
  String userId = 'acheteur-1',
  String projectId = 'projet-1',
  String source = 'cs_test_1',
  DateTime? grantedAt,
}) {
  final DateTime moment = grantedAt ?? DateTime.utc(2026, 1, 1);
  return EntitlementRecord(
    id: id,
    userId: userId,
    projectId: projectId,
    source: source,
    grantedAt: moment,
    createdAt: moment,
    amountInCents: 1200,
    currency: 'eur',
    authorShare: 9000,
    platformShare: 1000,
    authorAmountInCents: 1080,
    platformAmountInCents: 120,
  );
}

/// Un code promo.
PromoCodeRecord _promoCode({int maxUses = 100, DateTime? expiresAt}) {
  return PromoCodeRecord(
    code: 'BIENVENUE',
    discountType: PromoDiscountType.percent,
    value: 2500,
    currency: 'eur',
    maxUses: maxUses,
    maxUsesPerAccount: 1,
    expiresAt: expiresAt ?? DateTime.utc(2027, 1, 1),
    createdAt: DateTime.utc(2026, 1, 1),
  );
}
