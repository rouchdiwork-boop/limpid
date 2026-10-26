import 'package:limpid_api/limpid_api.dart';
import 'package:limpid_core/limpid_core.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';

import 'helpers/store_fixture.dart';

void main() {
  late SqliteDatabase database;
  late SqliteProjectStore projects;
  late SqliteSyncStore sync;
  late SqliteAuditLog audit;
  late AccountPurgeService worker;

  /// The moment of the deletion requests of the tests.
  final DateTime requestedAt = DateTime.utc(2026, 1, 1);

  /// The moment of the passes of the tests.
  final DateTime now = DateTime.utc(2026, 2, 1);

  setUp(() async {
    database = await SqliteDatabase.openInMemory();
    await SqliteMigrationRunner(
      database: database,
      directory: sqliteMigrationsDirectory,
    ).run();

    projects = SqliteProjectStore(database);
    sync = SqliteSyncStore(database);
    audit = SqliteAuditLog(database);
    worker = AccountPurgeService(
      store: SqlAccountPurgeStore(SqliteAccountPurgeDatabase(database)),
      audit: audit,
      logger: Logger(level: LogLevel.warning),
      workerId: 'worker-test',
    );
  });

  tearDown(() async {
    await database.close();
  });

  group('purge des comptes', () {
    test('efface les projets, les opérations et les collaborations d\'un '
        'compte dont l\'échéance est passée', () async {
      final String projectId = await _createProject(projects, 'user-1');
      await _pushOperation(sync, projectId, 'user-1');
      await _addMember(database, projectId, 'user-2');
      await _requestDeletion(audit, 'user-1', requestedAt);

      final PurgeReport report = await worker.run(now);

      expect(report.purged, hasLength(1));
      expect(report.purged.single.userId, 'user-1');
      expect(report.purged.single.outcome.projectsDeleted, 1);
      expect(report.purged.single.outcome.operationsDeleted, 1);
      expect(report.purged.single.outcome.collaborationsDeleted, 0);
      expect(report.failures, isEmpty);

      expect(await projects.listAll(userId: 'user-1'), isEmpty);
      expect(await sync.all(projectId: projectId), isEmpty);
      expect(await _countMembers(database, 'user-2'), 0);
    });

    test('efface la collaboration de l\'auteur sans toucher le livre du '
        'co-auteur', () async {
      final String own = await _createProject(projects, 'user-1');
      final String shared = await _createProject(projects, 'user-2');
      await _addMember(database, shared, 'user-1');
      await _requestDeletion(audit, 'user-1', requestedAt);

      final PurgeReport report = await worker.run(now);

      expect(report.purged, hasLength(1));
      expect(report.purged.single.outcome.collaborationsDeleted, 1);
      expect(await projects.listAll(userId: 'user-1'), isEmpty);
      expect(await projects.listAll(userId: 'user-2'), hasLength(1));
      expect(await sync.all(projectId: shared), isEmpty);
      expect(own, isNotEmpty);
    });

    test(
      'ne touche pas un compte dont l\'échéance n\'est pas passée',
      () async {
        final String projectId = await _createProject(projects, 'user-1');
        await _requestDeletion(audit, 'user-1', requestedAt);

        final PurgeReport report = await worker.run(DateTime.utc(2026, 1, 15));

        expect(report.purged, isEmpty);
        expect(report.skipped, isEmpty);
        expect(await projects.listAll(userId: 'user-1'), hasLength(1));
        expect(await sync.all(projectId: projectId), isEmpty);
      },
    );

    test(
      'ne touche pas un compte qui n\'a jamais demandé sa suppression',
      () async {
        await _createProject(projects, 'user-1');

        final PurgeReport report = await worker.run(now);

        expect(report.purged, isEmpty);
        expect(report.failures, isEmpty);
        expect(await projects.listAll(userId: 'user-1'), hasLength(1));
      },
    );

    test('est idempotent', () async {
      await _createProject(projects, 'user-1');
      await _requestDeletion(audit, 'user-1', requestedAt);

      final PurgeReport first = await worker.run(now);
      final PurgeReport second = await worker.run(now);

      expect(first.purged, hasLength(1));
      expect(second.purged, isEmpty);
      expect(second.skipped, <String>['user-1']);
      expect(second.failures, isEmpty);

      final List<AuditEntry> entries = await audit.entriesOf(
        userId: 'user-1',
        limit: 10,
        action: accountPurgedAction,
      );
      expect(entries, hasLength(1));
    });

    test(
      'écrit la trace de la purge et conserve les entrées d\'audit',
      () async {
        await _createProject(projects, 'user-1');
        await _requestDeletion(audit, 'user-1', requestedAt);

        await worker.run(now);

        final List<AuditEntry> entries = await audit.entriesOf(
          userId: 'user-1',
          limit: 10,
        );
        final List<AuditEntry> purges = entries
            .where((AuditEntry entry) => entry.action == accountPurgedAction)
            .toList(growable: false);
        expect(purges, hasLength(1));
        expect(purges.single.targetType, 'account');
        expect(purges.single.metadata['projects_deleted'], 1);
        expect(purges.single.metadata['worker_id'], 'worker-test');
        expect(purges.single.metadata['purged_at'], isA<String>());

        final List<AuditEntry> requests = await audit.entriesOf(
          userId: 'user-1',
          limit: 10,
          action: accountDeletionRequestedAction,
        );
        expect(requests, hasLength(1));
      },
    );

    test('continue après l\'échec d\'un compte', () async {
      await _createProject(projects, 'user-1');
      await _createProject(projects, 'user-2');
      await _requestDeletion(audit, 'user-1', requestedAt);
      await _requestDeletion(audit, 'user-2', requestedAt);

      final AccountPurgeService failing = AccountPurgeService(
        store: _FailingPurgeStore(
          SqlAccountPurgeStore(SqliteAccountPurgeDatabase(database)),
          'user-1',
        ),
        audit: audit,
        logger: Logger(level: LogLevel.warning),
        workerId: 'worker-test',
      );

      final PurgeReport report = await failing.run(now);

      expect(report.purged, hasLength(1));
      expect(report.purged.single.userId, 'user-2');
      expect(report.failures, hasLength(1));
      expect(report.failures.single.userId, 'user-1');
      expect(report.failures.single.reason, isNotEmpty);
      expect(await projects.listAll(userId: 'user-1'), hasLength(1));
      expect(await projects.listAll(userId: 'user-2'), isEmpty);
    });

    test('ne purge pas deux fois le même compte', () async {
      await _createProject(projects, 'user-1');
      await _requestDeletion(audit, 'user-1', requestedAt);

      final PurgeReport first = await worker.run(now);
      final PurgeReport second = await worker.run(now);

      expect(first.purged, hasLength(1));
      expect(second.purged, isEmpty);
    });

    test('efface les opérations écrites par l\'auteur sur le livre d\'un '
        'autre', () async {
      final String shared = await _createProject(projects, 'user-2');
      await _pushOperation(sync, shared, 'user-1');
      await _requestDeletion(audit, 'user-1', requestedAt);

      final PurgeReport report = await worker.run(now);

      expect(report.purged, hasLength(1));
      expect(report.purged.single.outcome.operationsDeleted, 1);
      expect(await sync.all(projectId: shared), isEmpty);
      expect(await projects.listAll(userId: 'user-2'), hasLength(1));
    });
  });

  group('planificateur', () {
    test('passe le worker et s\'arrête', () async {
      await _createProject(projects, 'user-1');
      await _requestDeletion(audit, 'user-1', requestedAt);
      final List<String> lines = <String>[];
      final AccountPurgeScheduler scheduler = AccountPurgeScheduler(
        service: worker,
        interval: const Duration(hours: 1),
        logger: Logger(level: LogLevel.info, sink: lines.add),
      );

      scheduler.start();
      expect(scheduler.isRunning, isTrue);
      await Future<void>.delayed(const Duration(milliseconds: 200));
      await scheduler.stop();

      expect(scheduler.isRunning, isFalse);
      expect(
        lines.any((String line) => line.contains('account.purge.completed')),
        isTrue,
      );
      expect(await projects.listAll(userId: 'user-1'), isEmpty);
    });
  });

  group('configuration du worker', () {
    test('a un délai par défaut', () {
      final AppConfig config = AppConfig.fromEnvironment(
        const <String, String>{},
      );

      expect(config.purgeInterval, defaultAccountPurgeInterval);
    });

    test('accepte la variable d\'environnement', () {
      final AppConfig config = AppConfig.fromEnvironment(const <String, String>{
        'LIMPID_PURGE_INTERVAL_SECONDS': '60',
      });

      expect(config.purgeInterval, const Duration(seconds: 60));
    });

    test('refuse un délai qui n\'est pas un entier positif', () {
      expect(
        () => AppConfig.fromEnvironment(const <String, String>{
          'LIMPID_PURGE_INTERVAL_SECONDS': '0',
        }),
        throwsA(isA<AppException>()),
      );
    });
  });
}

/// Creates a project owned by [ownerId].
Future<String> _createProject(ProjectStore projects, String ownerId) async {
  final ProjectRecord project = await projects.create(
    ownerId: ownerId,
    title: 'Le livre',
    synopsis: 'Un synopsis.',
    status: ManuscriptStatus.draft,
    language: 'fr-FR',
    orderKey: '5',
  );
  return project.id;
}

/// Pushes an operation written by [authorId] on [projectId].
Future<void> _pushOperation(
  SyncStore sync,
  String projectId,
  String authorId,
) async {
  await sync.append(
    projectId: projectId,
    operations: <SyncOpRecord>[
      SyncOpRecord(
        opId: 'op-$authorId',
        projectId: projectId,
        docId: 'doc-1',
        lamport: 1,
        authorId: authorId,
        type: 'insertBlock',
        payload: <String, dynamic>{
          'block_id': 'block-1',
          'content': 'Il pleuvait sur la falaise.',
        },
        schemaVersion: 1,
        createdAt: DateTime.utc(2026, 1, 1),
      ),
    ],
  );
}

/// Grants a role on a project, the way the sharing route does.
Future<void> _addMember(
  SqliteDatabase database,
  String projectId,
  String userId,
) async {
  await database.run(() {
    database.connection.execute(
      'INSERT INTO project_members '
      '(project_id, user_id, role, created_at) VALUES (?, ?, ?, ?)',
      <Object?>[
        projectId,
        userId,
        ProjectRole.coAuthor.name,
        SqliteValues.encodeTimestamp(DateTime.utc(2026, 1, 1)),
      ],
    );
  });
}

/// The number of collaborations of [userId] left in the database.
Future<int> _countMembers(SqliteDatabase database, String userId) async {
  return database.run(() {
    final ResultSet result = database.connection.select(
      'SELECT count(*) AS total FROM project_members WHERE user_id = ?',
      <Object?>[userId],
    );
    return result.isEmpty ? 0 : result.first['total']! as int;
  });
}

/// Journals the deletion request of an account, the way the route does.
Future<void> _requestDeletion(
  AuditLog audit,
  String userId,
  DateTime at,
) async {
  final AccountDeletionService service = AccountDeletionService(audit: audit);
  await service.request(
    userId: userId,
    email: '$userId@test.example',
    requestedAt: at,
  );
}

/// A store that fails on one account, to prove that the worker carries on.
final class _FailingPurgeStore implements AccountPurgeStore {
  const _FailingPurgeStore(this._delegate, this._failingUserId);

  final AccountPurgeStore _delegate;
  final String _failingUserId;

  @override
  Future<List<AuditEntry>> journalEntries({
    required String action,
    required int limit,
  }) {
    return _delegate.journalEntries(action: action, limit: limit);
  }

  @override
  Future<AccountPurgeOutcome> purge({
    required String userId,
    String? email,
    required DateTime requestedAt,
    required DateTime scheduledFor,
    required DateTime purgedAt,
    required String workerId,
  }) async {
    if (userId == _failingUserId) {
      throw const FormatException('The database is unreachable.');
    }
    return _delegate.purge(
      userId: userId,
      email: email,
      requestedAt: requestedAt,
      scheduledFor: scheduledFor,
      purgedAt: purgedAt,
      workerId: workerId,
    );
  }
}
