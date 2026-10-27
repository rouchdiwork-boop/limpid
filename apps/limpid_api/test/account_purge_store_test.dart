import 'dart:io';

import 'package:limpid_api/limpid_api.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';

import 'helpers/account_purge_contract.dart';
import 'helpers/store_fixture.dart';
import 'helpers/test_server.dart';

void main() {
  for (final MapEntry<String, Future<AccountPurgeFixture> Function()> entry
      in <String, Future<AccountPurgeFixture> Function()>{
        'mémoire': _inMemoryFixture,
        'SQLite': _sqliteFixture,
      }.entries) {
    runAccountPurgeContract(name: entry.key, build: entry.value);
  }

  group('déclaration des tables personnelles', () {
    test('déclare toutes les tables du schéma', () async {
      final SqliteDatabase database = await SqliteDatabase.openInMemory();
      addTearDown(database.close);
      await SqliteMigrationRunner(
        database: database,
        directory: sqliteMigrationsDirectory,
      ).run();

      final Set<String> schema = await _tablesOf(database);

      expect(
        schema.difference(PersonalDataTables.names),
        isEmpty,
        reason:
            'Une table du schéma n\'est pas déclarée : la purge '
            'n\'effacerait pas ses lignes. Déclare-la dans '
            'PersonalDataTables, avec la raison de la décision.',
      );
      expect(
        PersonalDataTables.names.difference(schema),
        isEmpty,
        reason:
            'Une table déclarée n\'existe pas dans le schéma : la '
            'déclaration et le schéma ne disent pas la même chose.',
      );
    });

    test('déclare toutes les tables des migrations Postgres', () {
      final Set<String> tables = _postgresTables();

      expect(
        tables.difference(PersonalDataTables.names),
        isEmpty,
        reason:
            'Une table du schéma Postgres n\'est pas déclarée : la '
            'purge n\'effacerait pas ses lignes en production.',
      );
    });
  });

  group('purge des données personnelles', () {
    late SqliteDatabase database;
    late SqlAccountPurgeStore store;

    setUp(() async {
      database = await SqliteDatabase.openInMemory();
      await SqliteMigrationRunner(
        database: database,
        directory: sqliteMigrationsDirectory,
      ).run();
      store = SqlAccountPurgeStore(SqliteAccountPurgeDatabase(database));
    });

    tearDown(() async {
      await database.close();
    });

    test(
      'efface une ligne de l\'auteur dans chaque table personnelle',
      () async {
        await _seedAuthor(database, 'user-1');
        final List<String> books = await _booksOf(database, 'user-1');

        for (final ErasedTable table in PersonalDataTables.erased) {
          expect(
            await _rowsOfAuthor(database, table, 'user-1', books),
            isPositive,
            reason:
                'la table ${table.name} ne porte aucune ligne de l\'auteur '
                'avant la purge : le test ne prouverait rien',
          );
        }

        final AccountPurgeOutcome outcome = await _purge(store, 'user-1');

        expect(outcome.purged, isTrue);
        expect(outcome.personalRowsDeleted, greaterThan(0));
        for (final ErasedTable table in PersonalDataTables.erased) {
          expect(
            await _rowsOfAuthor(database, table, 'user-1', books),
            0,
            reason:
                'la table ${table.name} porte encore une ligne de l\'auteur '
                'après la purge',
          );
        }
      },
    );

    test('ne touche pas aux lignes d\'un autre compte', () async {
      await _seedAuthor(database, 'user-1');
      await _seedAuthor(database, 'user-2');
      final List<String> books = await _booksOf(database, 'user-2');

      await _purge(store, 'user-1');

      for (final ErasedTable table in PersonalDataTables.erased) {
        expect(
          await _rowsOfAuthor(database, table, 'user-2', books),
          isPositive,
          reason:
              'la purge a effacé les lignes de l\'autre compte dans '
              '${table.name}',
        );
      }
    });

    test('efface l\'invitation reçue par l\'adresse du compte', () async {
      // L'invitation vise une adresse, pas un compte : elle porte l'adresse
      // de l'auteur, et elle doit disparaitre avec lui.
      await _insert(database, 'teams', <String, Object?>{
        'id': 'team-user-2',
        'name': 'Les auteurs',
        'owner_id': 'user-2',
        'created_at': _stamp,
        'updated_at': _stamp,
      });
      await _insert(database, 'team_invitations', <String, Object?>{
        'id': 'invitation-par-adresse',
        // L'equipe qui invite : l'invitation porte une cle etrangere vers
        // elle, elle doit donc exister.
        'team_id': 'team-user-2',
        'user_id': null,
        'email': 'auteur-1@example.com',
        'role': 'writer',
        'status': 'pending',
        'invited_by': 'user-2',
        'created_at': _stamp,
      });

      await _purge(store, 'user-1', email: 'auteur-1@example.com');

      expect(
        await _count(database, 'team_invitations', 'id = ?', <Object?>[
          'invitation-par-adresse',
        ]),
        0,
      );
    });

    test(
      'efface les opérations de l\'auteur sur le livre d\'un autre',
      () async {
        await _seedAuthor(database, 'user-2');
        await _insert(database, 'sync_ops', <String, Object?>{
          'id': 'op-partage',
          'project_id': 'project-user-2',
          'doc_id': 'doc-2',
          'lamport': 2,
          'author_id': 'user-1',
          'type': 'insertBlock',
          'payload': '{"block_id":"block-2"}',
          'schema_version': 1,
          'created_at': _stamp,
        });

        await _purge(store, 'user-1');

        expect(
          await _count(database, 'sync_ops', 'author_id = ?', <Object?>[
            'user-1',
          ]),
          0,
        );
        expect(
          await _count(database, 'projects', 'owner_id = ?', <Object?>[
            'user-2',
          ]),
          1,
        );
      },
    );

    test('est idempotente : une seconde purge ne casse rien', () async {
      await _seedAuthor(database, 'user-1');
      final AccountPurgeOutcome first = await _purge(store, 'user-1');
      await _insert(database, 'two_factor', <String, Object?>{
        'user_id': 'user-1',
        'secret': 'JBSWY3DPEHPK3PXP',
        'is_enabled': 1,
        'created_at': _stamp,
      });

      final AccountPurgeOutcome second = await _purge(
        store,
        'user-1',
        at: DateTime.utc(2026, 3, 1),
      );

      expect(first.purged, isTrue);
      expect(second.purged, isFalse);
      expect(second.personalRowsDeleted, 0);
      expect(
        await _count(database, 'two_factor', 'user_id = ?', <Object?>[
          'user-1',
        ]),
        1,
        reason: 'une ligne écrite après la purge doit survivre',
      );
    });

    test('garde le registre qui prouve que la purge a eu lieu', () async {
      await _seedAuthor(database, 'user-1');

      await _purge(store, 'user-1');

      expect(
        await _count(database, 'account_purges', 'user_id = ?', <Object?>[
          'user-1',
        ]),
        1,
      );
    });

    test('garde le journal d\'audit de l\'auteur', () async {
      await _seedAuthor(database, 'user-1');
      await _insert(database, 'audit_log', <String, Object?>{
        'id': 'entry-1',
        'user_id': 'user-1',
        'action': 'account.deletion_requested',
        'target_type': 'account',
        'target_id': 'user-1',
        'metadata': '{"email":"auteur@test.example"}',
        'ip': '203.0.113.4',
        'created_at': _stamp,
      });

      await _purge(store, 'user-1');

      expect(
        await _count(database, 'audit_log', 'user_id = ?', <Object?>['user-1']),
        1,
        reason: 'le journal d\'audit est conservé un an (D-19)',
      );
    });

    test('vide l\'administrateur des indicateurs sans les supprimer', () async {
      await _seedAuthor(database, 'user-1');

      await _purge(store, 'user-1');

      final List<Map<String, Object?>> flags = await _rows(
        database,
        'SELECT flag_key, is_enabled, updated_by FROM feature_flags '
        'WHERE flag_key = ?',
        <Object?>['flag-user-1'],
      );
      expect(flags, hasLength(1));
      expect(flags.single['updated_by'], '');
      expect(flags.single['is_enabled'], 1);
    });
  });

  group('magasin en mémoire', () {
    test('efface les mêmes tables que le magasin SQL', () async {
      final InMemoryAccountPurgeStore store = InMemoryAccountPurgeStore(
        entries: const <AuditEntry>[],
      );
      _seedInMemory(store, 'user-1');
      _seedInMemory(store, 'user-2');

      final AccountPurgeOutcome outcome = await store.purge(
        userId: 'user-1',
        requestedAt: DateTime.utc(2026, 1, 1),
        scheduledFor: DateTime.utc(2026, 1, 31),
        purgedAt: DateTime.utc(2026, 1, 31),
        workerId: 'worker-1',
      );

      expect(outcome.purged, isTrue);
      expect(outcome.personalRowsDeleted, greaterThan(0));
      expect(store.remainingRows('user-1'), 0);
      expect(store.remainingRows('user-2'), isPositive);
      expect(store.featureFlagOwners['flag-user-1'], '');
    });
  });
}

/// L'instant écrit dans les lignes créées par les tests.
final int _stamp = SqliteValues.encodeTimestamp(DateTime.utc(2026, 1, 1));

/// Construit la fixture du magasin en mémoire.
Future<AccountPurgeFixture> _inMemoryFixture() async {
  final InMemoryAuditLog audit = InMemoryAuditLog();
  final InMemoryAccountPurgeStore store = InMemoryAccountPurgeStore(
    entries: audit.entries,
  );

  return AccountPurgeFixture(
    store: store,
    journal: (AuditEntry entry) async {
      audit.entries.add(entry);
    },
    seed: (String userId) async {
      _seedInMemory(store, userId);
    },
    remainingRows: (String userId) async => store.remainingRows(userId),
    dispose: () async {},
  );
}

/// Construit la fixture du magasin SQLite, sur une base en mémoire.
Future<AccountPurgeFixture> _sqliteFixture() async {
  final SqliteDatabase database = await SqliteDatabase.openInMemory();
  await SqliteMigrationRunner(
    database: database,
    directory: sqliteMigrationsDirectory,
  ).run();

  final SqliteAuditLog audit = SqliteAuditLog(database);

  return AccountPurgeFixture(
    store: SqlAccountPurgeStore(SqliteAccountPurgeDatabase(database)),
    journal: (AuditEntry entry) => audit.record(entry),
    seed: (String userId) async {
      await _seedAuthor(database, userId);
    },
    remainingRows: (String userId) async => _remainingRows(database, userId),
    dispose: database.close,
  );
}

/// Crée les données d'un compte dans la base SQLite.
///
/// La fonction écrit une ligne dans chaque table personnelle du compte :
/// c'est ce qui permet à la suite de tests de vérifier que la purge
/// n'oublie aucune table.
Future<void> _seedAuthor(SqliteDatabase database, String userId) async {
  final String book = 'project-$userId';
  await _insert(database, 'projects', <String, Object?>{
    'id': book,
    'owner_id': userId,
    'title': 'Le livre',
    'synopsis': 'Un synopsis.',
    'status': 'draft',
    'language': 'fr-FR',
    'order_key': '5',
    'is_public': 0,
    'created_at': _stamp,
    'updated_at': _stamp,
  });
  await _insert(database, 'project_members', <String, Object?>{
    'project_id': book,
    'user_id': userId,
    'role': 'owner',
    'created_at': _stamp,
  });
  await _insert(database, 'sync_ops', <String, Object?>{
    'id': 'op-$userId',
    'project_id': book,
    'doc_id': 'doc-$userId',
    'lamport': 1,
    'author_id': userId,
    'type': 'insertBlock',
    'payload': '{"block_id":"block-1"}',
    'schema_version': 1,
    'created_at': _stamp,
  });
  await _insert(database, 'exports', <String, Object?>{
    'id': 'export-$userId',
    'user_id': userId,
    'project_id': book,
    'format': 'epub3',
    'cover': 'front',
    'status': 'succeeded',
    'created_at': _stamp,
  });
  await _insert(database, 'bundles', <String, Object?>{
    'id': 'bundle-$userId',
    'owner_id': userId,
    'title': 'Les deux livres',
    'project_ids': '[]',
    'price_cents': 1500,
    'currency': 'eur',
    'is_published': 1,
    'created_at': _stamp,
  });
  await _insert(database, 'comment_threads', <String, Object?>{
    'id': 'thread-$userId',
    'project_id': book,
    'mark_id': 'mark-1',
    'excerpt': 'Un extrait.',
    'is_resolved': 0,
    'created_at': _stamp,
    'updated_at': _stamp,
  });
  await _insert(database, 'comments', <String, Object?>{
    'id': 'comment-$userId',
    'thread_id': 'thread-$userId',
    'author_id': userId,
    'body': 'Un message.',
    'created_at': _stamp,
  });
  await _insert(database, 'series', <String, Object?>{
    'id': 'series-$userId',
    'project_id': book,
    'title': 'La série',
    'synopsis': '',
    'order_key': '5',
    'volume_ids': '[]',
    'created_at': _stamp,
    'updated_at': _stamp,
  });
  await _insert(database, 'volumes', <String, Object?>{
    'id': 'volume-$userId',
    'project_id': book,
    'series_id': 'series-$userId',
    'title': 'Le tome',
    'synopsis': '',
    'order_key': '5',
    'chapter_ids': '[]',
    'created_at': _stamp,
    'updated_at': _stamp,
  });
  await _insert(database, 'chapters', <String, Object?>{
    'id': 'chapter-$userId',
    'project_id': book,
    'volume_id': 'volume-$userId',
    'title': 'Le chapitre',
    'synopsis': '',
    'status': 'draft',
    'order_key': '5',
    'scene_ids': '[]',
    'target_word_count': 0,
    'created_at': _stamp,
    'updated_at': _stamp,
  });
  await _insert(database, 'scenes', <String, Object?>{
    'id': 'scene-$userId',
    'project_id': book,
    'chapter_id': 'chapter-$userId',
    'document_id': 'document-$userId',
    'title': 'La scène',
    'synopsis': '',
    'status': 'draft',
    'order_key': '5',
    'point_of_view': null,
    'word_count': 0,
    'target_word_count': 0,
    'created_at': _stamp,
    'updated_at': _stamp,
  });
  await _insert(database, 'two_factor', <String, Object?>{
    'user_id': userId,
    'secret': 'JBSWY3DPEHPK3PXP',
    'is_enabled': 1,
    'created_at': _stamp,
  });
  await _insert(database, 'ai_consents', <String, Object?>{
    'user_id': userId,
    'scope': 'text_to_third_party',
    'provider': 'anthropic',
    'is_granted': 1,
    'granted_at': _stamp,
  });
  await _insert(database, 'two_factor_recovery_codes', <String, Object?>{
    'user_id': userId,
    'code_hash': 'hash-$userId',
  });
  await _insert(database, 'account_plans', <String, Object?>{
    'user_id': userId,
    'plan': 'pro',
    'billing_period': 'monthly',
    'period_started_at': _stamp,
  });
  await _insert(database, 'quota_usage', <String, Object?>{
    'user_id': userId,
    'feature': 'ai',
    'period_key': '2026-01',
    'quantity': 3,
  });
  await _insert(database, 'api_keys', <String, Object?>{
    'id': 'key-$userId',
    'user_id': userId,
    'name': 'Clef',
    'key_hash': 'hash-$userId',
    'scopes': 'read',
    'is_active': 1,
    'created_at': _stamp,
  });
  await _insert(database, 'project_shares', <String, Object?>{
    'id': 'share-$userId',
    'project_id': book,
    'owner_id': userId,
    'token_hash': 'hash-$userId',
    'expires_at': _stamp,
    'is_revoked': 0,
    'created_at': _stamp,
  });
  await _insert(database, 'webhook_endpoints', <String, Object?>{
    'id': 'endpoint-$userId',
    'user_id': userId,
    'url': 'https://exemple.test/rappel',
    'events': 'publication.published',
    'secret': 'secret-$userId',
    'is_active': 1,
    'created_at': _stamp,
    'updated_at': _stamp,
  });
  await _insert(database, 'webhook_deliveries', <String, Object?>{
    'id': 'delivery-$userId',
    'endpoint_id': 'endpoint-$userId',
    'user_id': userId,
    'event': 'publication.published',
    'payload': '{"title":"Le livre"}',
    'status': 'delivered',
    'attempts': 1,
    'created_at': _stamp,
  });
  await _insert(database, 'teams', <String, Object?>{
    'id': 'team-$userId',
    'name': 'Les auteurs',
    'owner_id': userId,
    'created_at': _stamp,
    'updated_at': _stamp,
  });
  await _insert(database, 'team_members', <String, Object?>{
    'team_id': 'team-$userId',
    'user_id': userId,
    'role': 'owner',
    'created_at': _stamp,
  });
  await _insert(database, 'team_invitations', <String, Object?>{
    'id': 'invitation-$userId-1',
    'team_id': 'team-$userId',
    'user_id': userId,
    'role': 'writer',
    'invited_by': 'inviter-$userId',
    'created_at': _stamp,
  });
  await _insert(database, 'team_invitations', <String, Object?>{
    'id': 'invitation-$userId-2',
    'team_id': 'team-$userId',
    'user_id': 'guest-$userId',
    'role': 'writer',
    'invited_by': userId,
    'created_at': _stamp,
  });
  await _insert(database, 'kdp_publications', <String, Object?>{
    'id': 'publication-$userId',
    'project_id': book,
    'user_id': userId,
    'title': 'Le livre',
    'author': 'L\'auteur',
    'description': 'Un résumé.',
    'keywords': '[]',
    'categories': '[]',
    'issues': '[]',
    'isbn': '978-2-000000-00-$userId',
    'language': 'fr-FR',
    'publisher': 'Les éditions',
    'status': 'ready',
    'word_count': 1000,
    'page_count': 10,
    'epub_key': 'exports/clef.epub',
    'pdf_key': 'exports/clef.pdf',
    'epub_bytes': 100,
    'pdf_bytes': 200,
    'manuscript_version': '1',
    'created_at': _stamp,
  });
  await _insert(database, 'kdp_deposits', <String, Object?>{
    'id': 'deposit-$userId',
    'publication_id': 'publication-$userId',
    'user_id': userId,
    'status': 'pending',
    'issues': '[]',
    'attempts': 0,
    'created_at': _stamp,
    'updated_at': _stamp,
  });
  await _insert(database, 'book_sales', <String, Object?>{
    'project_id': book,
    'owner_id': userId,
    'title': 'Le livre',
    'price_cents': 1200,
    'currency': 'eur',
    'status': 'published',
    'author_share': 9000,
    'platform_share': 1000,
    'created_at': _stamp,
    'updated_at': _stamp,
  });
  await _insert(database, 'entitlements', <String, Object?>{
    'id': 'entitlement-$userId',
    'user_id': userId,
    'project_id': book,
    'source': 'cs-$userId',
    'granted_at': _stamp,
    'created_at': _stamp,
    'amount_cents': 1200,
    'currency': 'eur',
    'author_share': 9000,
    'platform_share': 1000,
    'author_amount_cents': 1080,
    'platform_amount_cents': 120,
  });
  await _insert(database, 'promo_code_usages', <String, Object?>{
    'id': 'usage-$userId',
    'code': 'bienvenue',
    'user_id': userId,
    'used_at': _stamp,
  });
  await _insert(database, 'feature_flags', <String, Object?>{
    'flag_key': 'flag-$userId',
    'is_enabled': 1,
    'description': 'Un indicateur',
    'updated_at': _stamp,
    'updated_by': userId,
  });
}

/// Crée les données d'un compte dans le magasin en mémoire.
///
/// La fonction écrit une ligne dans chaque table personnelle du compte :
/// elle est le miroir de [_seedAuthor], et le contrat de la purge compare
/// les deux implémentations.
void _seedInMemory(InMemoryAccountPurgeStore store, String userId) {
  final String book = 'project-$userId';
  store.addProject(projectId: book, ownerId: userId);
  store.addOperation(
    operationId: 'op-$userId',
    projectId: book,
    authorId: userId,
  );
  store.addMember(projectId: book, userId: userId);
  store.addRow(
    table: 'exports',
    rowId: 'export-$userId',
    owners: <String>{userId},
  );
  store.addRow(
    table: 'bundles',
    rowId: 'bundle-$userId',
    owners: <String>{userId},
  );
  store.addRow(
    table: 'comment_threads',
    rowId: 'thread-$userId',
    owners: <String>{},
    projectId: book,
  );
  store.addMessage(messageId: 'comment-$userId', authorId: userId);
  store.addRow(
    table: 'series',
    rowId: 'series-$userId',
    owners: <String>{},
    projectId: book,
  );
  store.addRow(
    table: 'volumes',
    rowId: 'volume-$userId',
    owners: <String>{},
    projectId: book,
  );
  store.addRow(
    table: 'chapters',
    rowId: 'chapter-$userId',
    owners: <String>{},
    projectId: book,
  );
  store.addRow(
    table: 'scenes',
    rowId: 'scene-$userId',
    owners: <String>{},
    projectId: book,
  );
  store.addRow(
    table: 'two_factor',
    rowId: 'two-factor-$userId',
    owners: <String>{userId},
  );
  store.addRow(
    table: 'two_factor_recovery_codes',
    rowId: 'recovery-$userId',
    owners: <String>{userId},
  );
  store.addRow(
    table: 'account_plans',
    rowId: 'plan-$userId',
    owners: <String>{userId},
  );
  store.addRow(
    table: 'quota_usage',
    rowId: 'quota-$userId',
    owners: <String>{userId},
  );
  store.addRow(
    table: 'api_keys',
    rowId: 'key-$userId',
    owners: <String>{userId},
  );
  store.addRow(
    table: 'project_shares',
    rowId: 'share-$userId',
    owners: <String>{userId},
  );
  store.addRow(
    table: 'ai_consents',
    rowId: 'consent-$userId',
    owners: <String>{userId},
  );
  store.addRow(
    table: 'webhook_endpoints',
    rowId: 'endpoint-$userId',
    owners: <String>{userId},
  );
  store.addRow(
    table: 'webhook_deliveries',
    rowId: 'delivery-$userId',
    owners: <String>{userId},
  );
  store.addRow(table: 'teams', rowId: 'team-$userId', owners: <String>{userId});
  store.addRow(
    table: 'team_members',
    rowId: 'team-$userId:$userId',
    owners: <String>{userId},
  );
  store.addRow(
    table: 'team_invitations',
    rowId: 'invitation-$userId-1',
    owners: <String>{userId, 'inviter-$userId'},
  );
  store.addRow(
    table: 'team_invitations',
    rowId: 'invitation-$userId-2',
    owners: <String>{'guest-$userId', userId},
  );
  store.addRow(
    table: 'kdp_publications',
    rowId: 'publication-$userId',
    owners: <String>{userId},
  );
  store.addRow(
    table: 'kdp_deposits',
    rowId: 'deposit-$userId',
    owners: <String>{userId},
  );
  store.addRow(
    table: 'book_sales',
    rowId: 'book-sale-$userId',
    owners: <String>{userId},
  );
  store.addRow(
    table: 'entitlements',
    rowId: 'entitlement-$userId',
    owners: <String>{userId},
  );
  store.addRow(
    table: 'promo_code_usages',
    rowId: 'usage-$userId',
    owners: <String>{userId},
  );
  store.addFeatureFlag(flagKey: 'flag-$userId', updatedBy: userId);
}

/// Insère une ligne dans une table, en nommant ses colonnes.
///
/// La fonction n'accepte que des colonnes connues : la ligne est écrite
/// avec des marqueurs de position, jamais par concaténation.
Future<void> _insert(
  SqliteDatabase database,
  String table,
  Map<String, Object?> values,
) async {
  final List<String> columns = values.keys.toList(growable: false);
  final String marks = List<String>.filled(columns.length, '?').join(', ');
  await database.run(() {
    database.connection.execute(
      'INSERT INTO $table (${columns.join(', ')}) VALUES ($marks)',
      columns.map((String column) => values[column]).toList(growable: false),
    );
  });
}

/// Le nombre de lignes du compte restées dans la base.
///
/// Le compte est fait avec la condition de la déclaration : la mesure porte
/// sur les lignes de l'auteur dans toutes les tables personnelles.
Future<int> _remainingRows(SqliteDatabase database, String userId) async {
  final List<String> counts = <String>[];
  final List<Object?> args = <Object?>[];
  for (final ErasedTable table in PersonalDataTables.erased) {
    counts.add(
      '(SELECT count(*) FROM ${table.name} WHERE ${table.ownerCondition})',
    );
    args.addAll(List<Object?>.filled(table.ownerCount, userId));
  }
  return database.run(() {
    final ResultSet result = database.connection.select(
      'SELECT ${counts.join(' + ')} AS total',
      args,
    );
    return result.isEmpty ? 0 : result.first['total']! as int;
  });
}

/// Le nombre de lignes de l'auteur dans la table [table].
///
/// La condition est celle de la déclaration, les livres de l'auteur étant
/// donnés par [books] : la mesure ne dépend pas de la présence des livres,
/// que la purge efface.
Future<int> _rowsOfAuthor(
  SqliteDatabase database,
  ErasedTable table,
  String userId,
  List<String> books,
) async {
  final List<String> clauses = <String>[
    for (final String column in table.ownerColumns) '$column = ?',
  ];
  final List<Object?> args = <Object?>[
    ...List<Object?>.filled(table.ownerColumns.length, userId),
  ];
  if (table.erasesProjects) {
    if (books.isEmpty) return 0;
    clauses.add(
      'project_id IN (${List<String>.filled(books.length, '?').join(', ')})',
    );
    args.addAll(books);
  }
  if (clauses.isEmpty) return 0;
  final String condition = clauses.length == 1
      ? clauses.single
      : '(${clauses.join(' OR ')})';
  return _count(database, table.name, condition, args);
}

/// Le nombre de lignes d'une table qui satisfont [condition].
Future<int> _count(
  SqliteDatabase database,
  String table,
  String condition,
  List<Object?> args,
) async {
  return database.run(() {
    final ResultSet result = database.connection.select(
      'SELECT count(*) AS total FROM $table WHERE $condition',
      args,
    );
    return result.isEmpty ? 0 : result.first['total']! as int;
  });
}

/// Les lignes d'une table, rendues comme des cartes.
Future<List<Map<String, Object?>>> _rows(
  SqliteDatabase database,
  String sql,
  List<Object?> args,
) async {
  return database.run(() {
    final ResultSet result = database.connection.select(sql, args);
    return result
        .map((Row row) => Map<String, Object?>.from(row))
        .toList(growable: false);
  });
}

/// Les identifiants des livres du compte.
Future<List<String>> _booksOf(SqliteDatabase database, String userId) async {
  final List<Map<String, Object?>> rows = await _rows(
    database,
    'SELECT id FROM projects WHERE owner_id = ? ORDER BY id',
    <Object?>[userId],
  );
  return rows.map((Map<String, Object?> row) => row['id']! as String).toList();
}

/// Les noms des tables de la base.
Future<Set<String>> _tablesOf(SqliteDatabase database) async {
  final List<Map<String, Object?>> rows = await _rows(
    database,
    "SELECT name FROM sqlite_master WHERE type = 'table'",
    const <Object?>[],
  );
  return rows.map((Map<String, Object?> row) => row['name']! as String).toSet();
}

/// Les noms des tables des migrations Postgres.
///
/// Le schéma de production est Postgres : une table qui n'y est pas
/// déclarée est une table dont la purge n'effacerait pas les lignes.
Set<String> _postgresTables() {
  final RegExp pattern = RegExp(
    r'CREATE\s+TABLE\s+IF\s+NOT\s+EXISTS\s+([a-z_]+)',
    caseSensitive: false,
  );
  final Set<String> tables = <String>{};
  for (final FileSystemEntity entity in Directory('db/migrations').listSync()) {
    if (entity is! File || !entity.path.endsWith('.sql')) continue;
    for (final RegExpMatch match in pattern.allMatches(
      entity.readAsStringSync(),
    )) {
      tables.add(match.group(1)!);
    }
  }
  return tables;
}

/// Lance la purge d'un compte.
Future<AccountPurgeOutcome> _purge(
  SqlAccountPurgeStore store,
  String userId, {
  DateTime? at,
  String? email,
}) {
  return store.purge(
    userId: userId,
    email: email,
    requestedAt: DateTime.utc(2026, 1, 1),
    scheduledFor: DateTime.utc(2026, 1, 31),
    purgedAt: at ?? DateTime.utc(2026, 2, 1),
    workerId: 'worker-1',
  );
}
