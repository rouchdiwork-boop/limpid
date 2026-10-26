import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:limpid_api/limpid_api.dart';
import 'package:limpid_core/limpid_core.dart';
import 'package:test/test.dart';

import 'helpers/store_fixture.dart';

void main() {
  late SqliteDatabase database;
  late SqliteProjectStore projects;
  late SqliteAuditLog audit;
  late SqlAccountPurgeStore purgeStore;
  late SqlAccountPurgeExternalStore externalStore;
  late InMemoryObjectStorage storage;
  late _FakeAuth auth;
  late List<String> logs;

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
    audit = SqliteAuditLog(database);
    purgeStore = SqlAccountPurgeStore(SqliteAccountPurgeDatabase(database));
    externalStore = SqlAccountPurgeExternalStore(
      SqliteAccountPurgeDatabase(database),
    );
    storage = InMemoryObjectStorage();
    auth = _FakeAuth();
    logs = <String>[];
  });

  tearDown(() async {
    await database.close();
  });

  /// Builds the worker under test.
  AccountPurgeService worker({
    ObjectStorageDeletion? objects,
    AccountAuthDeletion? accounts,
  }) {
    return AccountPurgeService(
      store: purgeStore,
      external: externalStore,
      auth: accounts ?? auth,
      storage: objects ?? storage,
      audit: audit,
      logger: Logger(level: LogLevel.warning, sink: logs.add),
      workerId: 'worker-test',
    );
  }

  /// Creates a project owned by [ownerId].
  Future<String> createProject(String ownerId) async {
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

  /// Journals the deletion request of an account, the way the route does.
  Future<void> requestDeletion(String userId) async {
    final AccountDeletionService service = AccountDeletionService(audit: audit);
    await service.request(
      userId: userId,
      email: '$userId@test.example',
      requestedAt: requestedAt,
    );
  }

  group('purge des tiers', () {
    test('efface le compte du service d\'authentification et les artefacts '
        'du stockage', () async {
      final String projectId = await createProject('user-1');
      await storage.put(
        key: 'exports/$projectId/livre.epub',
        bytes: Uint8List.fromList(<int>[1, 2, 3]),
        contentType: 'application/epub+zip',
      );
      await requestDeletion('user-1');

      final PurgeReport report = await worker().run(now);

      expect(report.purged, hasLength(1));
      expect(report.purged.single.userId, 'user-1');
      expect(report.failures, isEmpty);
      expect(auth.erased, <String>['user-1']);
      expect(storage.keys, isEmpty);
    });

    test('dérive les artefacts des projets du compte', () async {
      final String projectId = await createProject('user-1');
      await storage.put(
        key: '${ArtifactKeys.prefixOfProject(projectId)}livre.epub',
        bytes: Uint8List.fromList(<int>[1]),
        contentType: 'application/epub+zip',
      );
      await storage.put(
        key: 'exports/autre-projet/livre.epub',
        bytes: Uint8List.fromList(<int>[1]),
        contentType: 'application/epub+zip',
      );
      await requestDeletion('user-1');

      await worker().run(now);

      expect(storage.keys, <String>['exports/autre-projet/livre.epub']);
    });

    test('ne déclare le compte purgé qu\'une fois les tiers effacés', () async {
      final String projectId = await createProject('user-1');
      await storage.put(
        key: 'exports/$projectId/livre.epub',
        bytes: Uint8List.fromList(<int>[1]),
        contentType: 'application/epub+zip',
      );
      await requestDeletion('user-1');
      auth.failure = StateError('The authentication service refused.');

      final PurgeReport report = await worker().run(now);

      expect(report.purged, isEmpty);
      expect(report.failures, hasLength(1));
      expect(report.failures.single.userId, 'user-1');
      expect(await projects.listAll(userId: 'user-1'), isEmpty);

      final List<AuditEntry> entries = await audit.entriesOf(
        userId: 'user-1',
        limit: 10,
        action: accountPurgeIncompleteAction,
      );
      expect(entries, hasLength(1));
      expect(entries.single.metadata['reasons'], isNotEmpty);
    });

    test('réessaie à la passe suivante et termine la purge', () async {
      final String projectId = await createProject('user-1');
      await storage.put(
        key: 'exports/$projectId/livre.epub',
        bytes: Uint8List.fromList(<int>[1]),
        contentType: 'application/epub+zip',
      );
      await requestDeletion('user-1');
      auth.failure = StateError('The authentication service refused.');

      final PurgeReport first = await worker().run(now);
      auth.failure = null;
      final PurgeReport second = await worker().run(now);

      expect(first.purged, isEmpty);
      expect(second.purged, hasLength(1));
      expect(second.failures, isEmpty);
      expect(auth.erased, <String>['user-1']);
      expect(storage.keys, isEmpty);
    });

    test('n\'appelle pas les tiers une seconde fois', () async {
      final String projectId = await createProject('user-1');
      await storage.put(
        key: 'exports/$projectId/livre.epub',
        bytes: Uint8List.fromList(<int>[1]),
        contentType: 'application/epub+zip',
      );
      await requestDeletion('user-1');

      final PurgeReport first = await worker().run(now);
      final PurgeReport second = await worker().run(now);

      expect(first.purged, hasLength(1));
      expect(second.purged, isEmpty);
      expect(second.skipped, <String>['user-1']);
      expect(second.failures, isEmpty);
      expect(auth.erased, hasLength(1));
    });

    test('efface les artefacts même quand les projets ont disparu', () async {
      final String projectId = await createProject('user-1');
      await storage.put(
        key: 'exports/$projectId/livre.epub',
        bytes: Uint8List.fromList(<int>[1]),
        contentType: 'application/epub+zip',
      );
      await requestDeletion('user-1');
      final _FlakyStorage objects = _FlakyStorage(storage);
      objects.failingPrefix = 'exports/$projectId/';

      final PurgeReport first = await worker(objects: objects).run(now);

      expect(first.purged, isEmpty);
      expect(first.failures, hasLength(1));
      expect(await projects.listAll(userId: 'user-1'), isEmpty);

      objects.failingPrefix = null;
      final PurgeReport second = await worker(objects: objects).run(now);

      expect(second.purged, hasLength(1));
      expect(second.failures, isEmpty);
      expect(storage.keys, isEmpty);
      expect(
        objects.attempts.where(
          (String prefix) => prefix == 'exports/$projectId/',
        ),
        hasLength(2),
      );
    });

    test('efface les préfixes un par un', () async {
      final String first = await createProject('user-1');
      final String second = await createProject('user-1');
      await storage.put(
        key: 'exports/$first/livre.epub',
        bytes: Uint8List.fromList(<int>[1]),
        contentType: 'application/epub+zip',
      );
      await storage.put(
        key: 'exports/$second/livre.epub',
        bytes: Uint8List.fromList(<int>[1]),
        contentType: 'application/epub+zip',
      );
      await requestDeletion('user-1');
      final _FlakyStorage objects = _FlakyStorage(storage);
      objects.failingPrefix = 'exports/$first/';

      await worker(objects: objects).run(now);

      expect(storage.keys, <String>['exports/$first/livre.epub']);

      objects.failingPrefix = null;
      await worker(objects: objects).run(now);

      expect(storage.keys, isEmpty);
    });

    test('garde la trace des suppressions externes dans le journal', () async {
      final String projectId = await createProject('user-1');
      await storage.put(
        key: 'exports/$projectId/livre.epub',
        bytes: Uint8List.fromList(<int>[1]),
        contentType: 'application/epub+zip',
      );
      await requestDeletion('user-1');

      await worker().run(now);

      final List<AuditEntry> entries = await audit.entriesOf(
        userId: 'user-1',
        limit: 10,
        action: accountPurgedAction,
      );
      expect(entries, hasLength(1));
      expect(entries.single.metadata['auth_deleted_at'], isA<String>());
      expect(entries.single.metadata['storage_deleted_at'], isA<String>());
      expect(entries.single.metadata['artifacts_deleted'], 1);
      expect(entries.single.metadata['auth_configured'], isTrue);
      expect(entries.single.metadata['storage_configured'], isTrue);
    });

    test('efface le compte sans tiers configurés', () async {
      await createProject('user-1');
      await requestDeletion('user-1');

      final PurgeReport report = await AccountPurgeService(
        store: purgeStore,
        external: externalStore,
        audit: audit,
        logger: Logger(level: LogLevel.warning, sink: logs.add),
        workerId: 'worker-test',
      ).run(now);

      expect(report.purged, hasLength(1));
      expect(report.failures, isEmpty);
    });
  });

  group('client d\'administration Supabase', () {
    test('efface le compte', () async {
      final List<http.Request> requests = <http.Request>[];
      final http.Client client = MockClient((http.Request request) async {
        requests.add(request);
        return http.Response('{}', 200);
      });
      final SupabaseAccountAdmin admin = SupabaseAccountAdmin(
        baseUrl: 'https://project.test',
        serviceRoleKey: 'service-role-key',
        client: client,
      );

      await admin.deleteAccount(userId: 'user-1');

      expect(requests, hasLength(1));
      expect(requests.single.method, 'DELETE');
      expect(requests.single.url.path, '/auth/v1/admin/users/user-1');
      expect(requests.single.headers['apikey'], 'service-role-key');
    });

    test('accepte un compte déjà effacé', () async {
      final SupabaseAccountAdmin admin = SupabaseAccountAdmin(
        baseUrl: 'https://project.test',
        serviceRoleKey: 'service-role-key',
        client: MockClient(
          (http.Request request) async => http.Response('{}', 404),
        ),
      );

      await admin.deleteAccount(userId: 'user-1');
    });

    test('échoue proprement quand le service refuse', () async {
      final SupabaseAccountAdmin admin = SupabaseAccountAdmin(
        baseUrl: 'https://project.test',
        serviceRoleKey: 'service-role-key',
        client: MockClient(
          (http.Request request) async => http.Response('{}', 500),
        ),
      );

      await expectLater(
        admin.deleteAccount(userId: 'user-1'),
        throwsA(isA<AppException>()),
      );
    });

    test('ne laisse fuiter la clé du rôle de service', () async {
      final SupabaseAccountAdmin admin = SupabaseAccountAdmin(
        baseUrl: 'https://project.test',
        serviceRoleKey: 'service-role-key',
        client: MockClient(
          (http.Request request) async => http.Response('{}', 500),
        ),
      );

      try {
        await admin.deleteAccount(userId: 'user-1');
        fail('the call should have failed.');
      } on AppException catch (error) {
        expect(error.toString(), isNot(contains('service-role-key')));
        expect(error.details.toString(), isNot(contains('service-role-key')));
      }
    });
  });

  group('configuration', () {
    test('exige la clé du rôle de service en production', () {
      expect(
        () => AppConfig.fromEnvironment(const <String, String>{
          'LIMPID_PROFILE': 'prod',
          'SUPABASE_URL': 'https://project.test',
          'SUPABASE_ANON_KEY': 'anon',
          'REDIS_URL': 'redis://localhost:6379',
          'R2_ACCOUNT_ID': 'account',
          'R2_ACCESS_KEY_ID': 'key',
          'R2_SECRET_ACCESS_KEY': 'secret',
          'R2_BUCKET': 'bucket',
          'ANTHROPIC_API_KEY': 'ai',
          'STRIPE_SECRET_KEY': 'stripe',
          'DATABASE_URL': 'postgres://localhost/limpid',
        }),
        throwsA(isA<AppException>()),
      );
    });

    test('lit la clé du rôle de service', () {
      final AppConfig config = AppConfig.fromEnvironment(const <String, String>{
        'SUPABASE_SERVICE_ROLE_KEY': 'service-role-key',
      });

      expect(config.hasAuthAdmin, isTrue);
      expect(config.supabaseServiceRoleKey, 'service-role-key');
    });

    test('accepte un poste sans projet Supabase', () {
      final AppConfig config = AppConfig.fromEnvironment(
        const <String, String>{},
      );

      expect(config.hasAuthAdmin, isFalse);
      expect(config.supabaseServiceRoleKey, devPlaceholderSecret);
    });
  });

  group('stockage objet', () {
    test('efface les objets d\'un préfixe', () async {
      final InMemoryObjectStorage objects = InMemoryObjectStorage();
      await objects.put(
        key: 'exports/p1/a.epub',
        bytes: Uint8List.fromList(<int>[1]),
        contentType: 'application/epub+zip',
      );
      await objects.put(
        key: 'exports/p1/b.epub',
        bytes: Uint8List.fromList(<int>[1]),
        contentType: 'application/epub+zip',
      );
      await objects.put(
        key: 'exports/p2/a.epub',
        bytes: Uint8List.fromList(<int>[1]),
        contentType: 'application/epub+zip',
      );

      final int erased = await objects.deletePrefix(prefix: 'exports/p1/');

      expect(erased, 2);
      expect(objects.keys, <String>['exports/p2/a.epub']);
    });

    test('R2 liste les objets du préfixe et les efface', () async {
      final List<http.Request> requests = <http.Request>[];
      final http.Client client = MockClient((http.Request request) async {
        requests.add(request);
        if (request.method == 'GET') {
          return http.Response(
            '<?xml version="1.0" encoding="UTF-8"?>'
            '<ListBucketResult>'
            '<IsTruncated>false</IsTruncated>'
            '<Contents><Key>exports/p1/a.epub</Key></Contents>'
            '<Contents><Key>exports/p1/b&amp;c.epub</Key></Contents>'
            '</ListBucketResult>',
            200,
          );
        }
        return http.Response('', 204);
      });
      final R2ObjectStorage objects = R2ObjectStorage(
        endpoint: 'https://account.r2.cloudflarestorage.com',
        bucket: 'limpid',
        accessKeyId: 'access',
        secretAccessKey: 'secret',
        client: client,
      );

      final int erased = await objects.deletePrefix(prefix: 'exports/p1/');

      expect(erased, 2);
      final List<http.Request> deletions = requests
          .where((http.Request request) => request.method == 'DELETE')
          .toList(growable: false);
      expect(deletions, hasLength(2));
      expect(
        deletions.first.url.toString(),
        'https://account.r2.cloudflarestorage.com/limpid/exports/p1/a.epub',
      );
      expect(
        deletions.last.url.toString(),
        'https://account.r2.cloudflarestorage.com/limpid/exports/p1/b%26c.epub',
      );
      expect(deletions.first.headers['authorization'], contains('Credential='));
      final http.Request listing = requests.first;
      expect(listing.method, 'GET');
      expect(
        listing.url.query,
        'list-type=2&max-keys=1000&prefix=exports%2Fp1%2F',
      );
    });

    test(
      'R2 refuse l\'effacement quand le service répond une erreur',
      () async {
        final R2ObjectStorage objects = R2ObjectStorage(
          endpoint: 'https://account.r2.cloudflarestorage.com',
          bucket: 'limpid',
          accessKeyId: 'access',
          secretAccessKey: 'secret',
          client: MockClient(
            (http.Request request) async => http.Response('', 500),
          ),
        );

        await expectLater(
          objects.deletePrefix(prefix: 'exports/p1/'),
          throwsA(isA<StateError>()),
        );
      },
    );
  });
}

/// An authentication service that records the accounts it erased.
final class _FakeAuth implements AccountAuthDeletion {
  /// The error thrown by the next call, `null` when the call succeeds.
  Object? failure;

  /// The identifiers of the accounts that were erased.
  final List<String> erased = <String>[];

  @override
  bool get isConfigured => true;

  @override
  Future<void> deleteAccount({required String userId}) async {
    final Object? error = failure;
    if (error != null) throw error;
    erased.add(userId);
  }
}

/// A storage that refuses to erase one prefix.
final class _FlakyStorage implements ObjectStorageDeletion {
  /// Creates the storage on top of [delegate].
  _FlakyStorage(this.delegate);

  /// The storage that does the work.
  final ObjectStorageDeletion delegate;

  /// The prefix the storage refuses to erase, `null` when it accepts all.
  String? failingPrefix;

  /// The prefixes the erasure was tried on.
  final List<String> attempts = <String>[];

  @override
  Future<void> delete({required String key}) => delegate.delete(key: key);

  @override
  Future<int> deletePrefix({required String prefix}) async {
    attempts.add(prefix);
    if (prefix == failingPrefix) {
      throw StateError('The storage refused the prefix "$prefix".');
    }
    return delegate.deletePrefix(prefix: prefix);
  }
}
