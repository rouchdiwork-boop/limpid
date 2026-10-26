import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:limpid_app/src/data/app_database.dart';
import 'package:limpid_app/src/data/local_account_scope.dart';
import 'package:sqlite3/sqlite3.dart';

/// The move of a database created before the accounts were cloisonnés.
///
/// The device of an author who used the application before the update holds
/// tables without the account column: the move keeps the data of its
/// author.
void main() {
  test('une base sans compte garde les préférences de son auteur', () async {
    final Directory directory = await Directory.systemTemp.createTemp(
      'limpid-isolation',
    );
    addTearDown(() => directory.delete(recursive: true));
    final File file = File('${directory.path}/limpide.sqlite');

    final Database legacy = sqlite3.open(file.path);
    legacy.execute(
      'CREATE TABLE preferences (key TEXT PRIMARY KEY NOT NULL, '
      'value TEXT NOT NULL)',
    );
    legacy.execute(
      "INSERT INTO preferences (key, value) VALUES ('daily_goal', '2500')",
    );
    legacy.close();

    final AppDatabase database = await AppDatabase.openWith(
      NativeDatabase(file),
      accountScope: LocalAccountScope(() => 'author-a'),
    );
    addTearDown(database.close);

    expect(
      await database.manuscripts.readPreference(
        'daily_goal',
        accountId: 'author-a',
      ),
      '2500',
    );
    expect(
      await database.manuscripts.readPreference(
        'daily_goal',
        accountId: 'author-b',
      ),
      isNull,
    );
  });
}
