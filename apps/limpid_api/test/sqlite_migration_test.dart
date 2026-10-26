import 'package:limpid_api/src/db/sqlite_database.dart';
import 'package:limpid_api/src/db/sqlite_migration_runner.dart';
import 'package:limpid_api/src/db/sqlite_statement_splitter.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';

import 'helpers/store_fixture.dart';

void main() {
  group('runner de migrations SQLite', () {
    late SqliteDatabase database;

    setUp(() async {
      database = await SqliteDatabase.openInMemory();
    });

    tearDown(() async {
      await database.close();
    });

    test('applique les migrations du schéma', () async {
      final List<String> applied = await SqliteMigrationRunner(
        database: database,
        directory: sqliteMigrationsDirectory,
      ).run();

      expect(applied, <String>[
        '0001_projects.sql',
        '0002_project_members.sql',
        '0003_sync_ops.sql',
        '0004_audit_log.sql',
        '0005_comment_threads.sql',
        '0006_account_purges.sql',
        '0007_plans.sql',
        '0008_two_factor.sql',
        '0009_teams.sql',
        '0010_feature_flags.sql',
      ]);
    });

    test('crée les tables du schéma de référence', () async {
      await SqliteMigrationRunner(
        database: database,
        directory: sqliteMigrationsDirectory,
      ).run();

      final Set<String> tables = await _tables(database);
      expect(
        tables,
        containsAll(<String>[
          'projects',
          'project_members',
          'sync_ops',
          'audit_log',
          'comment_threads',
          'comments',
          'account_purges',
          'account_plans',
          'quota_usage',
          'two_factor',
          'two_factor_recovery_codes',
          'teams',
          'team_members',
          'team_invitations',
          'feature_flags',
          'schema_migrations',
        ]),
      );
    });

    test('crée les colonnes du schéma de référence', () async {
      await SqliteMigrationRunner(
        database: database,
        directory: sqliteMigrationsDirectory,
      ).run();

      expect(await _columns(database, 'projects'), <String>[
        'id',
        'owner_id',
        'title',
        'synopsis',
        'status',
        'language',
        'order_key',
        'is_public',
        'created_at',
        'updated_at',
        'deleted_at',
      ]);
      expect(await _columns(database, 'project_members'), <String>[
        'project_id',
        'user_id',
        'role',
        'created_at',
      ]);
      expect(await _columns(database, 'sync_ops'), <String>[
        'id',
        'project_id',
        'doc_id',
        'lamport',
        'author_id',
        'type',
        'payload',
        'schema_version',
        'created_at',
      ]);
      expect(await _columns(database, 'audit_log'), <String>[
        'id',
        'user_id',
        'action',
        'target_type',
        'target_id',
        'metadata',
        'ip',
        'created_at',
      ]);
      expect(await _columns(database, 'account_purges'), <String>[
        'user_id',
        'requested_at',
        'scheduled_for',
        'purged_at',
        'purged_by',
      ]);
      expect(await _columns(database, 'account_plans'), <String>[
        'user_id',
        'plan',
        'billing_period',
        'trial_ends_at',
        'period_started_at',
        'period_ends_at',
      ]);
      expect(await _columns(database, 'quota_usage'), <String>[
        'user_id',
        'feature',
        'period_key',
        'quantity',
      ]);
      expect(await _columns(database, 'two_factor'), <String>[
        'user_id',
        'secret',
        'is_enabled',
        'created_at',
        'enabled_at',
      ]);
      expect(await _columns(database, 'two_factor_recovery_codes'), <String>[
        'user_id',
        'code_hash',
        'used_at',
      ]);
      expect(await _columns(database, 'teams'), <String>[
        'id',
        'name',
        'owner_id',
        'created_at',
        'updated_at',
      ]);
      expect(await _columns(database, 'team_members'), <String>[
        'team_id',
        'user_id',
        'role',
        'created_at',
      ]);
      expect(await _columns(database, 'team_invitations'), <String>[
        'id',
        'team_id',
        'user_id',
        'role',
        'invited_by',
        'created_at',
      ]);
      expect(await _columns(database, 'feature_flags'), <String>[
        'flag_key',
        'is_enabled',
        'description',
        'updated_at',
        'updated_by',
      ]);
    });

    test('crée les index du schéma de référence', () async {
      await SqliteMigrationRunner(
        database: database,
        directory: sqliteMigrationsDirectory,
      ).run();

      expect(
        await _indexes(database, 'projects'),
        containsAll(<String>[
          'projects_owner_updated_idx',
          'projects_updated_idx',
        ]),
      );
      expect(
        await _indexes(database, 'project_members'),
        contains('project_members_user_idx'),
      );
      expect(
        await _indexes(database, 'sync_ops'),
        contains('sync_ops_project_lamport_idx'),
      );
      expect(
        await _indexes(database, 'audit_log'),
        contains('audit_log_user_created_idx'),
      );
      expect(
        await _indexes(database, 'account_purges'),
        contains('account_purges_purged_at_idx'),
      );
      expect(
        await _indexes(database, 'quota_usage'),
        contains('quota_usage_period_idx'),
      );
      expect(await _indexes(database, 'teams'), contains('teams_owner_idx'));
      expect(
        await _indexes(database, 'team_members'),
        contains('team_members_user_idx'),
      );
      expect(
        await _indexes(database, 'team_invitations'),
        contains('team_invitations_team_idx'),
      );
    });

    test('indexe les mêmes colonnes que Postgres', () async {
      await SqliteMigrationRunner(
        database: database,
        directory: sqliteMigrationsDirectory,
      ).run();

      expect(
        await _indexColumns(database, 'projects_owner_updated_idx'),
        <String>['owner_id', 'updated_at', 'id'],
      );
      expect(await _indexColumns(database, 'projects_updated_idx'), <String>[
        'updated_at',
        'id',
      ]);
      expect(
        await _indexColumns(database, 'sync_ops_project_lamport_idx'),
        <String>['project_id', 'lamport', 'author_id'],
      );
      expect(
        await _indexColumns(database, 'audit_log_user_created_idx'),
        <String>['user_id', 'created_at'],
      );
    });

    test('n\'applique rien à la seconde exécution', () async {
      final SqliteMigrationRunner runner = SqliteMigrationRunner(
        database: database,
        directory: sqliteMigrationsDirectory,
      );

      final List<String> first = await runner.run();
      final List<String> second = await runner.run();

      expect(first, hasLength(10));
      expect(second, isEmpty);
    });

    test('refuse un répertoire de migrations absent', () async {
      final SqliteMigrationRunner runner = SqliteMigrationRunner(
        database: database,
        directory: 'db/migrations/inexistant',
      );

      expect(runner.run(), throwsA(isA<StateError>()));
    });
  });

  group('découpe des instructions SQL', () {
    const SqlStatementSplitter splitter = SqlStatementSplitter();

    test('découpe sur les points-virgules', () {
      expect(splitter.split('SELECT 1; SELECT 2;'), <String>[
        'SELECT 1',
        'SELECT 2',
      ]);
    });

    test('ignore les point-virgules des chaînes', () {
      expect(splitter.split("SELECT 'un; deux' FROM t"), <String>[
        "SELECT 'un; deux' FROM t",
      ]);
    });

    test('ignore les point-virgules des commentaires', () {
      expect(
        splitter.split('-- un; deux\nSELECT 1;\n/* trois; quatre */'),
        <String>['-- un; deux\nSELECT 1'],
      );
    });

    test('ignore les point-virgules des identifiants cités', () {
      expect(splitter.split('SELECT "a;b" FROM t'), <String>[
        'SELECT "a;b" FROM t',
      ]);
    });

    test('laisse passer les dollars de la migration', () {
      expect(splitter.split("SELECT '\$1' FROM t"), <String>[
        r"SELECT '$1' FROM t",
      ]);
    });
  });
}

/// The names of the tables of the database.
Future<Set<String>> _tables(SqliteDatabase database) {
  return database.run(() {
    final ResultSet result = database.connection.select(
      "SELECT name FROM sqlite_master WHERE type = 'table'",
    );
    return result.map((Row row) => row['name']! as String).toSet();
  });
}

/// The names of the columns of a table.
Future<List<String>> _columns(SqliteDatabase database, String table) {
  return database.run(() {
    final ResultSet result = database.connection.select(
      'PRAGMA table_info($table)',
    );
    return result.map((Row row) => row['name']! as String).toList();
  });
}

/// The names of the explicit indexes of a table.
Future<List<String>> _indexes(SqliteDatabase database, String table) {
  return database.run(() {
    final ResultSet result = database.connection.select(
      "SELECT name FROM sqlite_master WHERE type = 'index' AND tbl_name = ? "
      "AND name NOT LIKE 'sqlite_autoindex%'",
      <Object?>[table],
    );
    return result.map((Row row) => row['name']! as String).toList();
  });
}

/// The columns of an index, in their declaration order.
Future<List<String>> _indexColumns(SqliteDatabase database, String index) {
  return database.run(() {
    final ResultSet result = database.connection.select(
      'PRAGMA index_info($index)',
    );
    return result.map((Row row) => row['name']! as String).toList();
  });
}
