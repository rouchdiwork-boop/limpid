import 'package:flutter_test/flutter_test.dart';
import 'package:limpid_app/src/data/app_database.dart';
import 'package:limpid_app/src/data/local_preferences_repository.dart';

import 'support.dart';

void main() {
  late AppDatabase database;

  setUp(() async {
    database = await openMemoryDatabase();
  });

  tearDown(() async {
    await database.close();
  });

  group('objectif quotidien', () {
    test(
      'vaut le défaut du design system quand rien n’est enregistré',
      () async {
        final LocalPreferencesRepository repository =
            LocalPreferencesRepository(database: database);

        expect(await repository.dailyGoal(), 1500);
        expect(LocalPreferencesRepository.defaultDailyGoal, 1500);
      },
    );

    test('enregistre la valeur choisie', () async {
      final LocalPreferencesRepository repository = LocalPreferencesRepository(
        database: database,
      );

      await repository.setDailyGoal(2500);

      expect(await repository.dailyGoal(), 2500);
    });

    test('ignore une valeur nulle', () async {
      final LocalPreferencesRepository repository = LocalPreferencesRepository(
        database: database,
      );
      await repository.setDailyGoal(2500);

      await repository.setDailyGoal(null);

      expect(await repository.dailyGoal(), 2500);
    });

    test('ignore une valeur négative', () async {
      final LocalPreferencesRepository repository = LocalPreferencesRepository(
        database: database,
      );
      await repository.setDailyGoal(2500);

      await repository.setDailyGoal(-100);

      expect(await repository.dailyGoal(), 2500);
    });

    test('ignore une valeur nulle quand rien n’est enregistré', () async {
      final LocalPreferencesRepository repository = LocalPreferencesRepository(
        database: database,
      );

      await repository.setDailyGoal(null);

      expect(await repository.dailyGoal(), 1500);
    });
  });

  group('série d’écriture', () {
    test('vaut zéro quand rien n’a été écrit', () async {
      final LocalPreferencesRepository repository = LocalPreferencesRepository(
        database: database,
        now: () => DateTime(2026, 10, 25, 10),
      );

      expect(await repository.writingStreak(), 0);
    });

    test('compte les jours consécutifs d’écriture', () async {
      final LocalPreferencesRepository repository = LocalPreferencesRepository(
        database: database,
        now: () => DateTime(2026, 10, 25, 10),
      );
      await _writeScene(database, 'scene-1', DateTime(2026, 10, 25, 9));
      await _writeScene(database, 'scene-2', DateTime(2026, 10, 24, 9));
      await _writeScene(database, 'scene-3', DateTime(2026, 10, 23, 9));

      expect(await repository.writingStreak(), 3);
    });

    test('s’arrête au jour sans écriture', () async {
      final LocalPreferencesRepository repository = LocalPreferencesRepository(
        database: database,
        now: () => DateTime(2026, 10, 25, 10),
      );
      await _writeScene(database, 'scene-1', DateTime(2026, 10, 25, 9));
      await _writeScene(database, 'scene-2', DateTime(2026, 10, 24, 9));
      await _writeScene(database, 'scene-3', DateTime(2026, 10, 22, 9));

      expect(await repository.writingStreak(), 2);
    });

    test('survit à un jour qui n’est pas terminé', () async {
      final LocalPreferencesRepository repository = LocalPreferencesRepository(
        database: database,
        now: () => DateTime(2026, 10, 25, 8),
      );
      await _writeScene(database, 'scene-1', DateTime(2026, 10, 24, 22));

      expect(await repository.writingStreak(), 1);
    });

    test('compte les scènes sans nombre de mots', () async {
      final LocalPreferencesRepository repository = LocalPreferencesRepository(
        database: database,
        now: () => DateTime(2026, 10, 25, 10),
      );
      await _writeScene(database, 'scene-1', DateTime(2026, 10, 25, 9));

      expect(await repository.writingStreak(), 1);
    });
  });
}

/// Writes a scene modified at [updatedAt].
Future<void> _writeScene(
  AppDatabase database,
  String sceneId,
  DateTime updatedAt,
) async {
  await database.manuscripts.saveScene(
    sceneOf(id: sceneId, updatedAt: updatedAt),
    projectId: 'project-1',
  );
}
