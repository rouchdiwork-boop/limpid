import 'dart:io';

import 'package:postgres/postgres.dart';

/// Applies the SQL migrations of a directory, in lexicographic order.
///
/// The runner is deliberately simple: it reads the `.sql` files, skips the
/// ones already recorded in `schema_migrations` and applies the others, each
/// in its own transaction.
final class MigrationRunner {
  /// Creates a runner.
  const MigrationRunner({required this.pool, required this.directory});

  /// The pool the migrations are applied to.
  final Pool<Object?> pool;

  /// The directory holding the `.sql` files.
  final String directory;

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
    await pool.execute(
      'CREATE TABLE IF NOT EXISTS schema_migrations ('
      ' name TEXT PRIMARY KEY,'
      ' applied_at TIMESTAMPTZ NOT NULL DEFAULT now()'
      ')',
    );
  }

  Future<Set<String>> _appliedMigrations() async {
    final Result result = await pool.execute(
      'SELECT name FROM schema_migrations',
    );
    return result
        .map((ResultRow row) => row.toColumnMap()['name']! as String)
        .toSet();
  }

  Future<void> _apply(String name, String sql) async {
    await pool.runTx((Session session) async {
      // Le protocole simple accepte plusieurs instructions par requête, ce
      // dont un fichier de migration a besoin.
      await session.execute(sql, queryMode: QueryMode.simple);
      await session.execute(
        'INSERT INTO schema_migrations (name) VALUES (\$1)',
        parameters: <Object?>[name],
      );
    });
  }
}
