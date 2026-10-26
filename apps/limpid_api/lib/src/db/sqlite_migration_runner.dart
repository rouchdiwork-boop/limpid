import 'dart:io';

import 'package:sqlite3/sqlite3.dart';

import 'sqlite_database.dart';
import 'sqlite_statement_splitter.dart';
import 'sqlite_values.dart';

/// Applies the SQLite migrations of a directory, in lexicographic order.
///
/// The runner mirrors the Postgres one: it reads the `.sql` files, skips the
/// ones already recorded in `schema_migrations` and applies the others, each
/// in its own transaction. A file that fails leaves the database untouched.
final class SqliteMigrationRunner {
  /// Creates a runner.
  const SqliteMigrationRunner({
    required this.database,
    required this.directory,
    this.splitter = const SqlStatementSplitter(),
  });

  /// The database the migrations are applied to.
  final SqliteDatabase database;

  /// The directory holding the `.sql` files.
  final String directory;

  /// The splitter cutting the files into statements.
  final SqlStatementSplitter splitter;

  /// The names of the migrations applied by this call.
  Future<List<String>> run() async {
    final Directory directory = Directory(this.directory);
    if (!directory.existsSync()) {
      throw StateError(
        'The migration directory "$this.directory" does not exist.',
      );
    }

    final List<File> files =
        directory
            .listSync()
            .whereType<File>()
            .where((File file) => file.path.endsWith('.sql'))
            .toList(growable: false)
          ..sort((File left, File right) => left.path.compareTo(right.path));

    await _ensureTrackingTable();
    final Set<String> applied = await _appliedMigrations();

    final List<String> executed = <String>[];
    for (final File file in files) {
      final String name = file.uri.pathSegments.last;
      if (applied.contains(name)) continue;
      await _apply(name, await file.readAsString());
      executed.add(name);
    }
    return executed;
  }

  Future<void> _ensureTrackingTable() async {
    await database.run(() {
      database.connection.execute(
        'CREATE TABLE IF NOT EXISTS schema_migrations ('
        ' name TEXT PRIMARY KEY,'
        ' applied_at INTEGER NOT NULL'
        ')',
      );
    });
  }

  Future<Set<String>> _appliedMigrations() async {
    return database.run(() {
      final ResultSet result = database.connection.select(
        'SELECT name FROM schema_migrations',
      );
      return result.map((Row row) => row['name']! as String).toSet();
    });
  }

  Future<void> _apply(String name, String sql) async {
    final List<String> statements = splitter.split(sql);
    await database.transaction(() {
      for (final String statement in statements) {
        database.connection.execute(statement);
      }
      database.connection.execute(
        'INSERT INTO schema_migrations (name, applied_at) VALUES (?, ?)',
        <Object?>[name, SqliteValues.encodeTimestamp(DateTime.now().toUtc())],
      );
    });
  }
}
