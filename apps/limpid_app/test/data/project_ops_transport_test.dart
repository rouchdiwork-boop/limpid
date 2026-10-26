import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:limpid_app/src/data/app_database.dart';
import 'package:limpid_app/src/data/local_sync_repository.dart';
import 'package:limpid_app/src/data/project_identity_store.dart';
import 'package:limpid_app/src/data/project_ops_transport.dart';
import 'package:limpid_app/src/domain/repositories.dart';
import 'package:limpid_core/limpid_core.dart';
import 'package:limpid_sync/limpid_sync.dart' hide SyncStatus;

import 'support.dart';

void main() {
  group('enregistrement du projet', () {
    test(
      'crée le projet sur le serveur avant de pousser ses opérations',
      () async {
        final AppDatabase database = await _databaseOf();
        addTearDown(database.close);
        final FakeApi api = FakeApi();

        final PushResult result = await _transportOf(
          database,
          api,
        ).push(<SyncOp>[insertBlockOp(documentId: 'document-1')]);

        expect(result.accepted, hasLength(1));
        expect(api.paths, <String>[
          '/v1/projects/project-1',
          '/v1/projects',
          '/v1/projects/${api.createdId}/ops',
        ]);

        final Map<String, Object?> declaration = api.declaration;
        expect(declaration['id'], 'project-1');
        expect(declaration['title'], 'Les Heures de Cendre');
        expect(declaration['synopsis'], 'Une archiviste et une cloche.');
        expect(declaration['language'], 'fr-FR');
      },
    );

    test('ne crée pas le projet deux fois', () async {
      final AppDatabase database = await _databaseOf();
      addTearDown(database.close);
      final FakeApi api = FakeApi();
      final ProjectOpsTransport transport = _transportOf(database, api);

      await transport.push(<SyncOp>[insertBlockOp(documentId: 'document-1')]);
      await transport.push(<SyncOp>[insertBlockOp(documentId: 'document-1')]);

      expect(api.creations, hasLength(1));
      expect(api.known, hasLength(1));
    });

    test('ne recrée pas un projet que le serveur connaît déjà', () async {
      final AppDatabase database = await _databaseOf();
      addTearDown(database.close);
      final FakeApi api = FakeApi();
      api.know('project-1', title: 'Les Heures de Cendre');

      final PushResult result = await _transportOf(
        database,
        api,
      ).push(<SyncOp>[insertBlockOp(documentId: 'document-1')]);

      expect(result.accepted, hasLength(1));
      expect(api.creations, isEmpty);
      expect(api.paths, <String>[
        '/v1/projects/project-1',
        '/v1/projects/project-1/ops',
      ]);
    });

    test(
      'laisse les opérations dans la file quand la création échoue',
      () async {
        final AppDatabase database = await _databaseOf();
        addTearDown(database.close);
        final FakeApi api = FakeApi(failsOnCreation: true);
        final ProjectOpsTransport transport = _transportOf(database, api);

        await expectLater(
          transport.push(<SyncOp>[insertBlockOp(documentId: 'document-1')]),
          throwsA(isA<SyncTransportException>()),
        );
        expect(api.pushed, isEmpty);
      },
    );

    test('laisse les opérations dans la file et signale l\'échec', () async {
      final AppDatabase database = await _databaseOf();
      addTearDown(database.close);
      final FakeApi api = FakeApi(failsOnCreation: true);
      final LocalSyncRepository repository = LocalSyncRepository(
        database: database,
        transport: _transportOf(database, api),
        author: const AuthorId('author-1'),
      );
      addTearDown(repository.dispose);

      await repository.synchronize();

      expect(repository.status, SyncStatus.offline);
      expect(await database.queueStore.all(), hasLength(1));
      expect(api.pushed, isEmpty);
    });

    test('porte is_public jusqu\'au serveur', () async {
      final AppDatabase database = await _databaseOf(isPublic: true);
      addTearDown(database.close);
      final FakeApi api = FakeApi();

      await _transportOf(
        database,
        api,
      ).push(<SyncOp>[insertBlockOp(documentId: 'document-1')]);

      expect(api.known[api.createdId]?['is_public'], isTrue);
      expect(api.changes, hasLength(1));
      expect(api.changes.single['is_public'], isTrue);
    });

    test('porte l\'état éditorial jusqu\'au serveur', () async {
      final AppDatabase database = await _databaseOf(isPublic: true);
      addTearDown(database.close);
      final FakeApi api = FakeApi();
      api.know('project-1');

      await _transportOf(
        database,
        api,
      ).push(<SyncOp>[insertBlockOp(documentId: 'document-1')]);

      expect(api.known['project-1']?['status'], 'published');
      expect(api.known['project-1']?['is_public'], isTrue);
      expect(api.changes, hasLength(1));
      expect(api.changes.single['status'], 'published');
      expect(api.changes.single['is_public'], isTrue);
    });
  });
}

/// Opens a database holding a project, a scene and a queued operation.
Future<AppDatabase> _databaseOf({bool isPublic = false}) async {
  final AppDatabase database = await openMemoryDatabase();
  await database.manuscripts.saveProject(
    isPublic
        ? projectOf().copyWith(
            status: ManuscriptStatus.published,
            isPublic: true,
          )
        : projectOf(),
  );
  await database.manuscripts.saveChapter(chapterOf(), projectId: 'project-1');
  await database.manuscripts.saveScene(sceneOf(), projectId: 'project-1');
  await database.queue.enqueue(insertBlockOp(documentId: 'document-1'));
  return database;
}

/// Builds a transport talking to the fake server.
ProjectOpsTransport _transportOf(AppDatabase database, FakeApi api) =>
    ProjectOpsTransport(
      baseUrl: Uri.parse('https://api.test'),
      client: MockClient(api.handle),
      store: database.manuscripts,
      projects: ProjectIdentityStore(database.sync, authorId: 'author-1'),
    );

/// The server of the tests.
///
/// The server behaves like the API: it **mints** the identifier of the
/// projects it creates, it answers `404` for a project it does not know, and
/// it refuses the operations of a project it does not know.
final class FakeApi {
  /// Creates a server.
  FakeApi({this.failsOnCreation = false});

  /// Whether the creation of a project fails.
  final bool failsOnCreation;

  /// The paths of the calls the server received.
  final List<String> paths = <String>[];

  /// The projects the server knows.
  final Map<String, Map<String, Object?>> known =
      <String, Map<String, Object?>>{};

  /// The bodies of the creations the server received.
  final List<Map<String, Object?>> creations = <Map<String, Object?>>[];

  /// The bodies of the updates the server received.
  final List<Map<String, Object?>> changes = <Map<String, Object?>>[];

  /// The operations the server accepted.
  final List<Object?> pushed = <Object?>[];

  /// The identifier of the last project the server created.
  String get createdId => known.keys.last;

  /// The body of the last creation.
  Map<String, Object?> get declaration => creations.last;

  /// Declares a project the server already knows.
  void know(String id, {String title = 'Titre'}) {
    known[id] = <String, Object?>{
      'id': id,
      'owner_id': 'author-1',
      'title': title,
      'synopsis': 'Synopsis.',
      'status': 'draft',
      'language': 'fr-FR',
      'order_key': '5',
      'is_public': false,
    };
  }

  /// Answers a request the way the API does.
  Future<http.Response> handle(http.Request request) async {
    final String path = request.url.path;
    paths.add(path);
    if (request.method == 'POST' && path == '/v1/projects') {
      return _create(request);
    }
    if (request.method == 'POST' && path.endsWith('/ops')) {
      return _push(request);
    }
    if (request.method == 'PATCH') {
      return _patch(request, path);
    }
    return _read(path);
  }

  /// Creates a project, with an identifier the server mints.
  Future<http.Response> _create(http.Request request) async {
    if (failsOnCreation) {
      return _error(500, 'internal_error', 'The server failed.');
    }
    final Map<String, Object?> body =
        jsonDecode(request.body) as Map<String, Object?>;
    creations.add(body);
    final String id = 'server-${known.length + 1}';
    know(id, title: body['title']! as String);
    final Map<String, Object?> project = known[id]!;
    project['synopsis'] = body['synopsis'];
    project['status'] = body['status'];
    project['language'] = body['language'];
    return _ok(project, 201);
  }

  /// Stores the operations of a project.
  Future<http.Response> _push(http.Request request) async {
    final Map<String, Object?> body =
        jsonDecode(request.body) as Map<String, Object?>;
    final List<Object?> operations = body['operations']! as List<Object?>;
    pushed.addAll(operations);
    return _ok(<String, Object?>{
      'accepted': operations,
      'duplicated': <Object?>[],
      'rejected': <Object?>[],
      'lamport_ack': 1,
    });
  }

  /// Updates the states of a project.
  Future<http.Response> _patch(http.Request request, String path) async {
    final Map<String, Object?> body =
        jsonDecode(request.body) as Map<String, Object?>;
    changes.add(body);
    final String id = path.substring('/v1/projects/'.length);
    final Map<String, Object?> project = known[id]!;
    project['status'] = body['status'] ?? project['status'];
    project['is_public'] = body['is_public'] ?? project['is_public'];
    return _ok(project);
  }

  /// Reads a project.
  Future<http.Response> _read(String path) async {
    final String id = path.substring('/v1/projects/'.length);
    final Map<String, Object?>? project = known[id];
    if (project == null) {
      return _error(404, 'not_found', 'The project does not exist.');
    }
    return _ok(project);
  }

  /// Answers a project.
  http.Response _ok(Map<String, Object?> data, [int status = 200]) =>
      http.Response(
        jsonEncode(<String, Object?>{'data': data}),
        status,
        headers: <String, String>{'content-type': 'application/json'},
      );

  /// Answers an error.
  http.Response _error(int status, String code, String message) =>
      http.Response(
        jsonEncode(<String, Object?>{
          'error': <String, Object?>{'code': code, 'message': message},
        }),
        status,
        headers: <String, String>{'content-type': 'application/json'},
      );
}
