import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:limpid_app/src/data/app_database.dart';
import 'package:limpid_app/src/data/local_sync_repository.dart';
import 'package:limpid_app/src/data/project_identity_store.dart';
import 'package:limpid_app/src/data/project_ops_transport.dart';
import 'package:limpid_app/src/domain/repositories.dart';
import 'package:limpid_core/limpid_core.dart' hide SyncTransport;
import 'package:limpid_sync/limpid_sync.dart' hide SyncEvent, SyncStatus;

import 'support.dart';

void main() {
  group('resynchronisation', () {
    test('un refus du serveur declenche une resynchronisation', () async {
      final AppDatabase database = await openMemoryDatabase();
      addTearDown(database.close);
      await _indexDocument(database);
      final FakeServer server = FakeServer();
      final LocalSyncRepository repository = _repositoryOf(database, server);
      addTearDown(repository.dispose);
      final List<SyncEvent> events = <SyncEvent>[];
      final StreamSubscription<SyncEvent> subscription = repository
          .watchEvents()
          .listen(events.add);
      addTearDown(subscription.cancel);

      await repository.synchronize();

      expect(server.treePulls, 1);
      expect(events.whereType<SyncResynchronizing>(), hasLength(1));
      expect(events.whereType<SyncResynchronized>(), hasLength(1));
      expect(repository.status, SyncStatus.synced);
    });

    test(
      'la resynchronisation remplace l\'etat local par celui du serveur',
      () async {
        final AppDatabase database = await openMemoryDatabase();
        addTearDown(database.close);
        await _indexDocument(database);
        final FakeServer server = FakeServer();
        final LocalSyncRepository repository = _repositoryOf(database, server);
        addTearDown(repository.dispose);

        await repository.synchronize();

        final DocumentSnapshot? snapshot = await database
            .snapshotsFor(() => 'author-1')
            .read(const DocumentId('document-1'));
        expect(snapshot, isNotNull);
        final CrdtDocument document = snapshot!.restore();
        final Block serverBlock = document.blocks.firstWhere(
          (Block block) => block.id.value == 'block-server',
        );
        expect(serverBlock.content.plainText, 'Le serveur fait autorite.');
        expect(serverBlock.parent, isNull);
      },
    );

    test('les operations locales non acceptees sont rejouees', () async {
      final AppDatabase database = await openMemoryDatabase();
      addTearDown(database.close);
      await _indexDocument(database);
      final FakeServer server = FakeServer();
      final LocalSyncRepository repository = _repositoryOf(database, server);
      addTearDown(repository.dispose);

      await repository.synchronize();

      // Le premier envoi est refuse, le second passe : l'operation a ete
      // rejouee apres la resynchronisation.
      expect(server.pushes, hasLength(2));
      expect(server.pushes.first, hasLength(1));
      expect(server.pushes.last, hasLength(1));
      expect(await database.queueStore.all(), isEmpty);
    });

    test('la synchronisation est retentee une seule fois', () async {
      final AppDatabase database = await openMemoryDatabase();
      addTearDown(database.close);
      await _indexDocument(database);
      final FakeServer server = FakeServer(refusalsLeft: 99);
      final LocalSyncRepository repository = _repositoryOf(database, server);
      addTearDown(repository.dispose);

      await repository.synchronize();

      // Le premier envoi et le seul nouvel essai : la boucle n'a pas
      // demarre.
      expect(server.pushes, hasLength(2));
      expect(server.treePulls, 1);
      expect(repository.status, SyncStatus.offline);
      // Rien n'est perdu : l'operation attend dans la file durable.
      expect(await database.queueStore.all(), hasLength(1));
    });

    test(
      'une operation refusee pour une autre raison est toujours signalee',
      () async {
        final AppDatabase database = await openMemoryDatabase();
        addTearDown(database.close);
        await _indexDocument(database);
        final FakeServer server = FakeServer(
          refusalsLeft: 0,
          refusesTheOperations: true,
        );
        final LocalSyncRepository repository = _repositoryOf(database, server);
        addTearDown(repository.dispose);
        final List<SyncEvent> events = <SyncEvent>[];
        final StreamSubscription<SyncEvent> subscription = repository
            .watchEvents()
            .listen(events.add);
        addTearDown(subscription.cancel);

        await repository.synchronize();
        await Future<void>.delayed(const Duration(milliseconds: 20));

        final SyncRefused refusal = events.whereType<SyncRefused>().single;
        expect(refusal.code, 'not_found');
        expect(refusal.message, contains("n'existe pas"));
        // L'operation n'est pas avalee : elle attend dans la file durable.
        expect(await database.queueStore.all(), hasLength(1));
      },
    );

    test('l\'interface ne demande rien a l\'utilisateur', () async {
      final AppDatabase database = await openMemoryDatabase();
      addTearDown(database.close);
      await _indexDocument(database);
      final FakeServer server = FakeServer();
      final LocalSyncRepository repository = _repositoryOf(database, server);
      addTearDown(repository.dispose);
      final List<SyncStatus> statuses = <SyncStatus>[];
      final StreamSubscription<SyncStatus> subscription = repository
          .watch()
          .listen(statuses.add);
      addTearDown(subscription.cancel);

      await repository.synchronize();
      await Future<void>.delayed(Duration.zero);

      // La synchronisation recommence, et l'interface ne demande rien :
      // aucun conflit, aucune fenetre, aucune exception.
      expect(
        statuses,
        containsAllInOrder(<SyncStatus>[SyncStatus.syncing, SyncStatus.synced]),
      );
      expect(
        statuses.where((SyncStatus status) => status == SyncStatus.conflict),
        isEmpty,
      );
    });
  });
}

/// Builds a repository talking to the fake server.
LocalSyncRepository _repositoryOf(AppDatabase database, FakeServer server) =>
    LocalSyncRepository(
      database: database,
      transport: ProjectOpsTransport(
        baseUrl: Uri.parse('https://api.test'),
        client: MockClient(server.handle),
        store: database.manuscripts,
        projects: ProjectIdentityStore(database.sync, authorId: 'author-1'),
      ),
      author: const AuthorId('author-1'),
    );

/// Indexes a document, so the synchronisation knows the project it belongs
/// to, and queues an operation the server has not accepted yet.
Future<void> _indexDocument(AppDatabase database) async {
  await database.manuscripts.saveProject(projectOf());
  await database.manuscripts.saveChapter(chapterOf(), projectId: 'project-1');
  await database.manuscripts.saveScene(sceneOf(), projectId: 'project-1');
  await database.queue.enqueue(insertBlockOp(documentId: 'document-1'));
}

/// The server of the tests.
///
/// The server knows the project and answers the tree of its documents. It
/// refuses the operations with the code of the protocol version until the
/// test lets it accept them.
final class FakeServer {
  /// Creates a server.
  FakeServer({this.refusalsLeft = 1, this.refusesTheOperations = false});

  /// The number of pushes the server refuses with the code of the protocol
  /// version before it accepts them.
  int refusalsLeft;

  /// Whether the server refuses the operations it receives.
  bool refusesTheOperations;

  /// The paths of the calls the server received.
  final List<String> paths = <String>[];

  /// The operations of every push the server received.
  final List<List<Object?>> pushes = <List<Object?>>[];

  /// The number of times the tree of the project was pulled.
  int treePulls = 0;

  /// Answers a request the way the API does.
  Future<http.Response> handle(http.Request request) async {
    final String path = request.url.path;
    paths.add(path);
    if (request.method == 'GET' && path == '/v1/projects/project-1') {
      return _ok(<String, Object?>{
        'id': 'project-1',
        'owner_id': 'author-1',
        'title': 'Les Heures de Cendre',
        'synopsis': 'Une archiviste et une cloche.',
        'status': 'draft',
        'language': 'fr-FR',
        'order_key': '5',
        'is_public': false,
      });
    }
    if (request.method == 'GET' && path.endsWith('/tree')) {
      treePulls++;
      return _ok(<Object?>[_tree]);
    }
    if (request.method == 'GET' && path.endsWith('/ops')) {
      return _ok(<Object?>[]);
    }
    if (request.method == 'POST' && path.endsWith('/ops')) {
      return _push(request);
    }
    return _error(404, 'not_found', 'The route does not exist.');
  }

  /// Stores the operations of a push.
  Future<http.Response> _push(http.Request request) async {
    final Map<String, Object?> body =
        jsonDecode(request.body) as Map<String, Object?>;
    final List<Object?> operations = body['operations']! as List<Object?>;
    pushes.add(operations);
    if (refusalsLeft > 0) {
      refusalsLeft--;
      return _error(
        409,
        'schema_version_unsupported',
        'This version of the protocol is no longer supported.',
      );
    }
    if (refusesTheOperations) {
      final Object? first = operations.isEmpty ? null : operations.first;
      return _ok(<String, Object?>{
        'accepted': <Object?>[],
        'duplicated': <Object?>[],
        'rejected': <Object?>[
          <String, Object?>{
            'op_id': first is Map<String, Object?> ? first['op_id'] : null,
            'code': 'not_found',
            'message': "Ce document n'existe pas dans ce projet.",
            'field': 'doc_id',
          },
        ],
        'lamport_ack': 1,
      });
    }
    return _ok(<String, Object?>{
      'accepted': operations,
      'duplicated': <Object?>[],
      'rejected': <Object?>[],
      'lamport_ack': 3,
    });
  }

  /// The tree of the document of the tests.
  Map<String, Object?> get _tree => <String, Object?>{
    'doc_id': 'document-1',
    'lamport': 7,
    'meta': <String, Object?>{},
    'operation_count': 2,
    'blocks': <Object?>[
      <String, Object?>{
        'id': 'block-server',
        'parent_id': null,
        'order_key': '5',
        'type': 'paragraph',
        'content': 'Le serveur fait autorite.',
        'lamport': 7,
        'author_id': 'auteur-2',
        'deleted': false,
        'version': 1,
        'marks': <String, Object?>{},
        'children': <Object?>[],
      },
    ],
  };

  /// Answers a payload.
  http.Response _ok(Object? data) => http.Response(
    jsonEncode(<String, Object?>{'data': data}),
    200,
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
