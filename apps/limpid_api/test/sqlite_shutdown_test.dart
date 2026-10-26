import 'dart:io';

import 'package:limpid_api/limpid_api.dart';
import 'package:test/test.dart';

/// Checks that the development database is released properly when the API
/// stops.
///
/// The SQLite file is opened in write-ahead-log mode: the journal lives in a
/// companion file until the last connection closes it. A server that stops
/// without closing its database leaves that journal on disk, and the next
/// start has to replay it.
void main() {
  group('arrêt de la base SQLite', () {
    late Directory directory;

    setUp(() {
      directory = Directory.systemTemp.createTempSync('limpid-sqlite');
    });

    tearDown(() {
      if (directory.existsSync()) {
        directory.deleteSync(recursive: true);
      }
    });

    test('la fermeture libère le fichier et son journal', () async {
      final String path = '${directory.path}/limpid.db';
      final SqliteDatabase database = await SqliteDatabase.open(path);
      await SqliteMigrationRunner(
        database: database,
        directory: 'db/migrations/sqlite',
      ).run();

      await database.run(() {
        database.connection.execute(
          'INSERT INTO projects (id, owner_id, title, synopsis, status, '
          'language, order_key, is_public, created_at, updated_at) '
          'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
          <Object?>[
            'project-1',
            'user-1',
            'Titre',
            '',
            'draft',
            'fr-FR',
            '5',
            0,
            SqliteValues.encodeTimestamp(DateTime.now().toUtc()),
            SqliteValues.encodeTimestamp(DateTime.now().toUtc()),
          ],
        );
      });

      expect(File(path).existsSync(), isTrue);
      expect(
        File('$path-wal').existsSync(),
        isTrue,
        reason: 'The write-ahead log should exist while the base is open.',
      );

      await database.close();

      expect(File(path).existsSync(), isTrue);
      expect(
        File('$path-wal').existsSync(),
        isFalse,
        reason: 'Closing the base should release its write-ahead log.',
      );
    });

    test('la fermeture des dépendances libère la base', () async {
      final String path = '${directory.path}/limpid.db';
      final SqliteDatabase database = await SqliteDatabase.open(path);
      await SqliteMigrationRunner(
        database: database,
        directory: 'db/migrations/sqlite',
      ).run();

      final AppDependencies dependencies = await buildProductionDependencies(
        await _config(path),
        sqliteDatabase: database,
      );
      await dependencies.close();

      expect(
        File('$path-wal').existsSync(),
        isFalse,
        reason: 'Stopping the server should release the write-ahead log.',
      );
    });
  });
}

/// Builds a development configuration pointing at [path].
Future<AppConfig> _config(String path) async {
  return AppConfig.fromEnvironment(<String, String>{
    'LIMPID_PROFILE': 'dev',
    'LIMPID_DB_DRIVER': 'sqlite',
    'LIMPID_DB_PATH': path,
    'PORT': '0',
  });
}
