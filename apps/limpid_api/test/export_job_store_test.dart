import 'package:limpid_api/src/db/export_job_record.dart';
import 'package:limpid_api/src/db/export_job_store.dart';
import 'package:limpid_api/src/db/in_memory_export_job_store.dart';
import 'package:limpid_api/src/db/sqlite_database.dart';
import 'package:limpid_api/src/db/sqlite_export_job_store.dart';
import 'package:limpid_api/src/db/sqlite_migration_runner.dart';
import 'package:test/test.dart';

import 'helpers/store_fixture.dart';

void main() {
  _exportJobContract('memoire', () async => InMemoryExportJobStore());
  _exportJobContract('SQLite', () async {
    final SqliteDatabase database = await SqliteDatabase.openInMemory();
    await SqliteMigrationRunner(
      database: database,
      directory: sqliteMigrationsDirectory,
    ).run();
    return SqliteExportJobStore(database);
  });
}

/// Le contrat du port des travaux d'export, exécuté contre chaque
/// implémentation.
void _exportJobContract(String name, Future<ExportJobStore> Function() build) {
  group('travaux d\'export — $name', () {
    late ExportJobStore store;

    setUp(() async {
      store = await build();
    });

    test('range un travail et le relit', () async {
      final ExportJobRecord job = _job('job-1');

      await store.insert(job);

      final ExportJobRecord? found = await store.findById('job-1');
      expect(found, isNotNull);
      expect(found!.id, 'job-1');
      expect(found.userId, 'user-1');
      expect(found.projectId, 'project-1');
      expect(found.format, 'epub3');
      expect(found.cover, 'front');
      expect(found.status, ExportJobStatus.queued);
      expect(found.createdAt, job.createdAt);
    });

    test('relit un travail absent comme absent', () async {
      expect(await store.findById('job-1'), isNull);
    });

    test('remplace le travail rangé', () async {
      await store.insert(_job('job-1'));

      await store.update(
        _job('job-1').copyWith(
          status: ExportJobStatus.succeeded,
          artifactKey: 'exports/project-1/livre.epub',
        ),
      );

      final ExportJobRecord? found = await store.findById('job-1');
      expect(found!.status, ExportJobStatus.succeeded);
      expect(found.artifactKey, 'exports/project-1/livre.epub');
    });

    test(
      'la file rend les travaux en attente, les plus anciens d\'abord',
      () async {
        await store.insert(_job('job-2', createdAt: _moment(2)));
        await store.insert(_job('job-1', createdAt: _moment(1)));
        await store.insert(
          _job(
            'job-3',
            createdAt: _moment(3),
          ).copyWith(status: ExportJobStatus.succeeded),
        );

        final List<ExportJobRecord> queued = await store.listQueued();

        expect(queued.map((ExportJobRecord job) => job.id), <String>[
          'job-1',
          'job-2',
        ]);
      },
    );

    test(
      'la liste du compte rend ses travaux, les plus récents d\'abord',
      () async {
        await store.insert(_job('job-1', createdAt: _moment(1)));
        await store.insert(_job('job-2', createdAt: _moment(2)));
        await store.insert(
          _job('job-3', userId: 'user-2', createdAt: _moment(3)),
        );

        final List<ExportJobRecord> owned = await store.listByUser(
          userId: 'user-1',
        );

        expect(owned.map((ExportJobRecord job) => job.id), <String>[
          'job-2',
          'job-1',
        ]);
      },
    );

    test('les travaux expirés sont ceux dont l\'artefact a disparu', () async {
      await store.insert(
        _job(
          'job-1',
        ).copyWith(status: ExportJobStatus.succeeded, expiresAt: _moment(1)),
      );
      await store.insert(
        _job(
          'job-2',
        ).copyWith(status: ExportJobStatus.succeeded, expiresAt: _moment(10)),
      );
      await store.insert(_job('job-3'));

      final List<ExportJobRecord> expired = await store.listExpired(
        now: _moment(5),
      );

      expect(expired.map((ExportJobRecord job) => job.id), <String>['job-1']);
    });

    test('un travail en échec n\'est jamais expire', () async {
      await store.insert(
        _job(
          'job-1',
        ).copyWith(status: ExportJobStatus.failed, expiresAt: _moment(1)),
      );

      final List<ExportJobRecord> expired = await store.listExpired(
        now: _moment(5),
      );

      expect(expired, isEmpty);
    });
  });
}

/// Un travail d'export de test.
ExportJobRecord _job(
  String id, {
  String userId = 'user-1',
  DateTime? createdAt,
}) {
  return ExportJobRecord(
    id: id,
    userId: userId,
    projectId: 'project-1',
    format: 'epub3',
    cover: 'front',
    status: ExportJobStatus.queued,
    createdAt: createdAt ?? _moment(1),
  );
}

/// L'instant [index] de la journée de référence.
DateTime _moment(int index) => DateTime.utc(2026, 10, 26, 9, index);
