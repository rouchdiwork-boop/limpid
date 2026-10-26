import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:limpid_app/src/data/app_database.dart';
import 'package:limpid_app/src/data/local_sync_repository.dart';
import 'package:limpid_app/src/data/project_identity_store.dart';
import 'package:limpid_app/src/data/project_ops_transport.dart';
import 'package:limpid_app/src/domain/repositories.dart';
import 'package:limpid_core/limpid_core.dart';

import 'support.dart';

void main() {
  late Directory directory;

  setUp(() {
    directory = Directory.systemTemp.createTempSync('limpid-data-test');
  });

  tearDown(() {
    if (directory.existsSync()) directory.deleteSync(recursive: true);
  });

  group('file d’attente', () {
    test('survit à une fermeture et à une réouverture de la base', () async {
      final File file = File('${directory.path}/limpid.sqlite');
      AppDatabase database = await openFileDatabase(file);
      await database.manuscripts.saveProject(projectOf());
      await database.queue.enqueue(insertBlockOp(documentId: 'document-1'));
      await database.close();

      database = await openFileDatabase(file);
      final entries = await database.queueStore.all();

      expect(entries, hasLength(1));
      expect(entries.first.operationKey, 'document-1/1/author-1');
      expect(entries.first.documentId, 'document-1');
      await database.close();
    });
  });

  group('synchronize', () {
    test(
      'laisse le statut hors ligne et ne lève pas quand le serveur est injoignable',
      () async {
        final AppDatabase database = await openMemoryDatabase();
        addTearDown(database.close);
        await _indexDocument(database);

        final LocalSyncRepository repository = LocalSyncRepository(
          database: database,
          transport: _transportOf(database, _unreachable),
          author: const AuthorId('author-1'),
        );
        addTearDown(repository.dispose);

        await repository.synchronize();

        expect(repository.status, SyncStatus.offline);
        expect(await database.queueStore.all(), hasLength(1));
      },
    );

    test(
      'laisse la file intacte quand le serveur renvoie une erreur',
      () async {
        final AppDatabase database = await openMemoryDatabase();
        addTearDown(database.close);
        await _indexDocument(database);

        final LocalSyncRepository repository = LocalSyncRepository(
          database: database,
          transport: _transportOf(database, _serverError),
          author: const AuthorId('author-1'),
        );
        addTearDown(repository.dispose);

        await repository.synchronize();

        expect(repository.status, SyncStatus.offline);
        expect(await database.queueStore.all(), hasLength(1));
      },
    );

    test(
      'pousse les opérations et vide la file quand le serveur répond',
      () async {
        final AppDatabase database = await openMemoryDatabase();
        addTearDown(database.close);
        await _indexDocument(database);

        final List<Map<String, Object?>> pushed = <Map<String, Object?>>[];
        final LocalSyncRepository repository = LocalSyncRepository(
          database: database,
          transport: _transportOf(
            database,
            (http.Request request) => _answer(request, pushed),
          ),
          author: const AuthorId('author-1'),
        );
        addTearDown(repository.dispose);

        await repository.synchronize();

        expect(repository.status, SyncStatus.synced);
        expect(pushed, hasLength(1));
        expect(pushed.first['doc_id'], 'document-1');
        expect(await database.queueStore.all(), isEmpty);
      },
    );

    test('publie les états sur le flux', () async {
      final AppDatabase database = await openMemoryDatabase();
      addTearDown(database.close);
      await _indexDocument(database);

      final LocalSyncRepository repository = LocalSyncRepository(
        database: database,
        transport: _transportOf(
          database,
          (http.Request request) => _answer(request, <Map<String, Object?>>[]),
        ),
        author: const AuthorId('author-1'),
      );
      addTearDown(repository.dispose);

      final List<SyncStatus> statuses = <SyncStatus>[];
      final subscription = repository.watch().listen(statuses.add);
      addTearDown(subscription.cancel);

      await repository.synchronize();
      await Future<void>.delayed(Duration.zero);

      expect(
        statuses,
        containsAllInOrder(<SyncStatus>[SyncStatus.syncing, SyncStatus.synced]),
      );
    });
  });
}

/// Indexes a document, so the synchronisation knows the project it belongs
/// to.
Future<void> _indexDocument(AppDatabase database) async {
  await database.manuscripts.saveProject(projectOf());
  await database.manuscripts.saveChapter(chapterOf(), projectId: 'project-1');
  await database.manuscripts.saveScene(sceneOf(), projectId: 'project-1');
  await database.queue.enqueue(insertBlockOp(documentId: 'document-1'));
}

/// Builds a transport talking to a fake server.
ProjectOpsTransport _transportOf(
  AppDatabase database,
  Future<http.Response> Function(http.Request request) handler,
) => ProjectOpsTransport(
  baseUrl: Uri.parse('https://api.test'),
  client: MockClient(handler),
  store: database.manuscripts,
  projects: ProjectIdentityStore(database.sync, authorId: 'author-1'),
);

/// A server that cannot be reached.
Future<http.Response> _unreachable(http.Request request) async =>
    throw http.ClientException('Connection refused', request.url);

/// A server that answers an error.
Future<http.Response> _serverError(http.Request request) async => http.Response(
  jsonEncode(<String, Object?>{
    'error': <String, Object?>{
      'code': 'internal_error',
      'message': 'The server failed.',
    },
  }),
  500,
  headers: <String, String>{'content-type': 'application/json'},
);

/// A server that answers an empty journal.
Future<http.Response> _emptyAnswer(http.Request request) async => http.Response(
  jsonEncode(<String, Object?>{'data': <Object?>[]}),
  200,
  headers: <String, String>{'content-type': 'application/json'},
);

/// A server that acknowledges the operations it receives.
Future<http.Response> _answer(
  http.Request request,
  List<Map<String, Object?>> pushed,
) async {
  if (request.method == 'GET') {
    if (request.url.path == '/v1/projects/project-1') return _knownProject();
    return _emptyAnswer(request);
  }
  if (request.method == 'POST' && request.url.path == '/v1/projects') {
    return _createdProject(request);
  }
  final Object? decoded = jsonDecode(request.body);
  final Map<String, Object?> payload = decoded is Map<String, Object?>
      ? decoded
      : <String, Object?>{};
  final Object? raw = payload['operations'];
  final List<Object?> operations = raw is List<Object?>
      ? raw
      : const <Object?>[];
  pushed.addAll(operations.whereType<Map<String, Object?>>());
  return http.Response(
    jsonEncode(<String, Object?>{
      'data': <String, Object?>{
        'accepted': operations,
        'duplicated': <Object?>[],
        'rejected': <Object?>[],
        'lamport_ack': 1,
      },
    }),
    200,
    headers: <String, String>{'content-type': 'application/json'},
  );
}

/// A server that knows the project of the tests.
Future<http.Response> _knownProject() async => http.Response(
  jsonEncode(<String, Object?>{
    'data': <String, Object?>{
      'id': 'project-1',
      'owner_id': 'author-1',
      'title': 'Les Heures de Cendre',
      'synopsis': 'Une archiviste et une cloche.',
      'status': 'draft',
      'language': 'fr-FR',
      'order_key': '5',
      'is_public': false,
    },
  }),
  200,
  headers: <String, String>{'content-type': 'application/json'},
);

/// A server that creates the project of the tests.
Future<http.Response> _createdProject(http.Request request) async {
  final Object? decoded = jsonDecode(request.body);
  final Map<String, Object?> body = decoded is Map<String, Object?>
      ? decoded
      : <String, Object?>{};
  return http.Response(
    jsonEncode(<String, Object?>{
      'data': <String, Object?>{
        'id': body['id'],
        'owner_id': 'author-1',
        'title': body['title'],
        'synopsis': body['synopsis'],
        'status': body['status'],
        'language': body['language'],
        'order_key': '5',
        'is_public': false,
      },
    }),
    201,
    headers: <String, String>{'content-type': 'application/json'},
  );
}
