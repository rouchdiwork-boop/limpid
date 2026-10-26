import 'dart:async';

import 'package:limpid_app/src/data/app_database.dart';
import 'package:limpid_app/src/data/document_op_queue_store.dart';
import 'package:limpid_app/src/data/manuscript_store.dart';
import 'package:limpid_app/src/data/project_ops_transport.dart';
import 'package:limpid_app/src/domain/repositories.dart';
import 'package:limpid_core/limpid_core.dart' hide SyncTransport;
import 'package:limpid_sync/limpid_sync.dart' hide SyncStatus;

/// The synchronisation of the local database with the server.
///
/// The repository never throws: an unreachable server leaves the status at
/// [SyncStatus.offline] and the queue intact — the operations wait in the
/// durable queue and are pushed again when the network comes back, with the
/// retry policy of `limpid_sync`.
///
/// ## The transport
///
/// The transport is injected and **shared**: it addresses the routes of the
/// API for every document of the library. It must therefore not own the HTTP
/// client: the synchronisation client of `limpid_sync` releases the
/// transport at the end of every round.
final class LocalSyncRepository implements SyncRepository {
  /// Creates a repository.
  LocalSyncRepository({
    required this.database,
    required this.transport,
    required this.author,
    this.retryPolicy = const RetryPolicy(),
  });

  /// The local database of the application.
  final AppDatabase database;

  /// The transport reaching the API.
  final SyncTransport transport;

  /// The author of the local operations.
  final AuthorId author;

  /// The policy applied to the operations the server refused.
  final RetryPolicy retryPolicy;

  final StreamController<SyncStatus> _statuses =
      StreamController<SyncStatus>.broadcast();

  SyncStatus _status = SyncStatus.offline;

  @override
  SyncStatus get status => _status;

  @override
  Stream<SyncStatus> watch() => _statuses.stream;

  @override
  Future<void> synchronize() async {
    _emit(SyncStatus.syncing);
    var hasFailure = false;
    var hasConflict = false;
    try {
      final List<DocumentBinding> bindings = await database.manuscripts
          .listDocumentBindings(author.value);
      for (final DocumentBinding binding in bindings) {
        final _RoundOutcome outcome = await _synchronize(binding.documentId);
        if (outcome == _RoundOutcome.failed) hasFailure = true;
        if (outcome == _RoundOutcome.conflict) hasConflict = true;
      }
      if (await _registerTheBooksWithoutScene(bindings)) {
        hasFailure = true;
      }
    } on Object {
      hasFailure = true;
    }
    if (hasConflict) {
      _emit(SyncStatus.conflict);
      return;
    }
    _emit(hasFailure ? SyncStatus.offline : SyncStatus.synced);
  }

  /// Registers the books of the author that have no scene.
  ///
  /// A book without a scene has no operation to push: the server would never
  /// learn about it, and the showcase would not show it. The registration is
  /// idempotent — a book the server already knows is not created twice.
  Future<bool> _registerTheBooksWithoutScene(
    List<DocumentBinding> bindings,
  ) async {
    final SyncTransport current = transport;
    if (current is! ProjectRegisteringTransport) {
      return false;
    }
    var hasFailure = false;
    final Set<String> pushed = bindings
        .map((DocumentBinding binding) => binding.projectId)
        .toSet();
    for (final Project project in await database.manuscripts.listProjects(
      author.value,
    )) {
      if (pushed.contains(project.id.value)) {
        continue;
      }
      try {
        await current.registerProject(project.id.value);
      } on Object {
        hasFailure = true;
      }
    }
    return hasFailure;
  }

  /// Releases the resources held by the repository.
  Future<void> dispose() => _statuses.close();

  /// Synchronises one document, and reports how the round went.
  Future<_RoundOutcome> _synchronize(String documentId) async {
    final DocumentOpQueueStore store = DocumentOpQueueStore(
      delegate: database.queueStore,
      documentId: documentId,
    );
    final SyncClient client = SyncClient(
      documentId: DocumentId(documentId),
      authorId: author,
      transport: transport,
      queueStore: store,
      snapshotStore: database.snapshots,
      queue: OpQueue(store: store, retryPolicy: retryPolicy),
      failOnConflict: true,
    );
    try {
      await client.sync(documentId);
      return client.state.isOnline
          ? _RoundOutcome.synced
          : _RoundOutcome.failed;
    } on SyncConflictException {
      return _RoundOutcome.conflict;
    } on Object {
      return _RoundOutcome.failed;
    } finally {
      await client.dispose();
    }
  }

  /// Publishes a new status.
  void _emit(SyncStatus status) {
    if (_statuses.isClosed) return;
    _status = status;
    _statuses.add(status);
  }
}

/// The outcome of a synchronisation round.
enum _RoundOutcome {
  /// The document is synchronised with the server.
  synced,

  /// The server could not be reached, or refused the operations.
  failed,

  /// The document holds a divergence the author must arbitrate.
  conflict,
}
