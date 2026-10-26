import 'package:drift/drift.dart' show QueryRow;
import 'package:flutter_test/flutter_test.dart';
import 'package:limpid_app/src/data/app_database.dart';
import 'package:limpid_app/src/data/writing_session_store.dart';
import 'package:limpid_app/src/domain/repositories.dart';

import 'support.dart';

void main() {
  late AppDatabase database;

  setUp(() async {
    database = await openMemoryDatabase();
  });

  tearDown(() async {
    await database.close();
  });

  group('séances d’écriture', () {
    test('enregistre les mots du jour', () async {
      await database.writingSessions.recordWriting(
        day: DateTime(2026, 10, 25, 9, 30),
        projectId: 'project-1',
        words: 120,
        minutes: 12,
      );

      final List<WritingSession> sessions = await database.writingSessions
          .listWritingSessions(
            from: DateTime(2026, 10, 25),
            to: DateTime(2026, 10, 25),
          );

      expect(sessions, hasLength(1));
      expect(sessions.single.words, 120);
      expect(sessions.single.minutes, 12);
      expect(sessions.single.day, DateTime(2026, 10, 25));
    });

    test('additionne les mots d’une seconde frappe du même jour', () async {
      await database.writingSessions.recordWriting(
        day: DateTime(2026, 10, 25, 9, 30),
        projectId: 'project-1',
        words: 120,
        minutes: 12,
      );
      await database.writingSessions.recordWriting(
        day: DateTime(2026, 10, 25, 10, 15),
        projectId: 'project-1',
        words: 30,
        minutes: 4,
      );

      final List<WritingSession> sessions = await database.writingSessions
          .listWritingSessions(
            from: DateTime(2026, 10, 25),
            to: DateTime(2026, 10, 25),
          );

      expect(sessions, hasLength(1));
      expect(sessions.single.words, 150);
      expect(sessions.single.minutes, 16);
    });

    test('garde une ligne par livre et une ligne pour le total', () async {
      await database.writingSessions.recordWriting(
        day: DateTime(2026, 10, 25, 9, 30),
        projectId: 'project-1',
        words: 120,
        minutes: 12,
      );
      await database.writingSessions.recordWriting(
        day: DateTime(2026, 10, 25, 10, 15),
        projectId: 'project-2',
        words: 30,
        minutes: 4,
      );

      final List<QueryRow> rows = await database.sync
          .customSelect(
            'SELECT project_id, words FROM writing_sessions ORDER BY project_id',
          )
          .get();

      expect(rows.map((QueryRow row) => row.data['project_id']), <String>[
        '',
        'project-1',
        'project-2',
      ]);
      expect(rows.first.data['words'], 150);
    });

    test('liste les jours sur lesquels l’auteur a écrit', () async {
      await database.writingSessions.recordWriting(
        day: DateTime(2026, 10, 25, 9, 30),
        projectId: 'project-1',
        words: 120,
        minutes: 12,
      );
      await database.writingSessions.recordWriting(
        day: DateTime(2026, 10, 23, 22, 10),
        projectId: 'project-1',
        words: 40,
        minutes: 5,
      );

      final List<DateTime> days = await database.writingSessions
          .listWritingDays();

      expect(days, <DateTime>[DateTime(2026, 10, 23), DateTime(2026, 10, 25)]);
    });

    test(
      'liste les séances d’une plage, de la plus récente à la plus ancienne',
      () async {
        await database.writingSessions.recordWriting(
          day: DateTime(2026, 10, 23, 22, 10),
          projectId: 'project-1',
          words: 40,
          minutes: 5,
        );
        await database.writingSessions.recordWriting(
          day: DateTime(2026, 10, 25, 9, 30),
          projectId: 'project-1',
          words: 120,
          minutes: 12,
        );

        final List<WritingSession> sessions = await database.writingSessions
            .listWritingSessions(
              from: DateTime(2026, 10, 20),
              to: DateTime(2026, 10, 26),
            );

        expect(sessions.map((WritingSession session) => session.words), <int>[
          120,
          40,
        ]);
      },
    );

    test('ne compte pas les jours situés hors de la plage', () async {
      await database.writingSessions.recordWriting(
        day: DateTime(2026, 10, 10, 9, 30),
        projectId: 'project-1',
        words: 90,
        minutes: 9,
      );

      final List<WritingSession> sessions = await database.writingSessions
          .listWritingSessions(
            from: DateTime(2026, 10, 20),
            to: DateTime(2026, 10, 26),
          );

      expect(sessions, isEmpty);
    });

    test('n’écrit jamais sur le réseau', () async {
      await database.writingSessions.recordWriting(
        day: DateTime(2026, 10, 25, 9, 30),
        projectId: 'project-1',
        words: 120,
        minutes: 12,
      );

      // La session vit dans la base de l'appareil : la file des opérations
      // qui partent vers le serveur reste vide.
      expect(await database.queueStore.all(), isEmpty);
      expect(await database.writingSessions.listWritingDays(), <DateTime>[
        DateTime(2026, 10, 25),
      ]);
    });

    test('cloisonne les séances par compte', () async {
      await database.writingSessions.recordWriting(
        day: DateTime(2026, 10, 25, 9, 30),
        projectId: 'project-1',
        words: 120,
        minutes: 12,
        accountId: 'another-account',
      );

      expect(await database.writingSessions.listWritingDays(), isEmpty);
      expect(
        await database.writingSessions.listWritingDays(
          accountId: 'another-account',
        ),
        <DateTime>[DateTime(2026, 10, 25)],
      );
    });
  });

  group('la clé du jour', () {
    test('est le jour local du moment', () {
      expect(dayKeyOf(DateTime(2026, 10, 25, 23, 30)), '2026-10-25');
      expect(dayKeyOf(DateTime(2026, 10, 26, 0, 30)), '2026-10-26');
    });

    test('retrouve le jour local de la clé', () {
      expect(dayOfKey('2026-10-25'), DateTime(2026, 10, 25));
    });

    test('refuse une clé corrompue', () {
      expect(dayOfKey('hier'), isNull);
      expect(dayOfKey('2026-10'), isNull);
    });
  });
}
