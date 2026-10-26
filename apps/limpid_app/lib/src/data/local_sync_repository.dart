import 'dart:async';

import 'package:limpid_app/src/data/account_op_queue_store.dart';
import 'package:limpid_app/src/data/account_snapshot_store.dart';
import 'package:limpid_app/src/data/app_database.dart';
import 'package:limpid_app/src/data/document_op_queue_store.dart';
import 'package:limpid_app/src/data/manuscript_store.dart';
import 'package:limpid_app/src/data/project_ops_transport.dart';
import 'package:limpid_app/src/data/real_time_transport.dart';
import 'package:limpid_app/src/data/sync_resynchronizer.dart';
import 'package:limpid_app/src/domain/errors.dart';
import 'package:limpid_app/src/domain/realtime.dart';
import 'package:limpid_app/src/domain/repositories.dart';
import 'package:limpid_core/limpid_core.dart' hide SyncTransport;
import 'package:limpid_sync/limpid_sync.dart' hide SyncEvent, SyncStatus;

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
///
/// ## The relay
///
/// The real-time relay is an **accelerator**: the queue of the synchronisation
/// REST remains the source of truth. The repository follows the documents it
/// is asked to follow, applies the operations the relay delivers to the
/// durable journal of the device, and falls back on the queue REST every
/// time the channel reopens.
///
/// ## The account of the synchronisation
///
/// The synchronisation pushes the operations of the account that is signed
/// in, and only those: the queue of another account never leaves the device
/// under this session. The account is resolved on every round.
///
/// ## The resynchronization
///
/// The server refuses the version of the protocol of the client with
/// `409 schema_version_unsupported`: the client does not speak the language
/// of the server any more. It then pulls the tree of the project, replaces
/// its local state by the one of the server, replays the operations the
/// server has not accepted yet and retries the synchronisation **once**.
///
/// The author is never asked anything: the interface sees a synchronisation
/// that starts again, and nothing else.
final class LocalSyncRepository
    implements RealTimeSyncRepository, SyncEventSource {
  /// Creates a repository.
  ///
  /// The account of the synchronisation is [currentAuthor] when it is given,
  /// and the author of the constructor otherwise.
  LocalSyncRepository({
    required this.database,
    required this.transport,
    required this.author,
    AuthorId Function()? currentAuthor,
    this.retryPolicy = const RetryPolicy(),
    this.realTime,
  }) : _currentAuthor = currentAuthor ?? (() => author) {
    final SyncTransport current = transport;
    if (current is RejectionReportingTransport) {
      _refusals = current.refusals.listen(_publishRefusal);
    }
  }

  /// The local database of the application.
  final AppDatabase database;

  /// The transport reaching the API.
  final SyncTransport transport;

  /// The author of the local operations.
  final AuthorId author;

  final AuthorId Function() _currentAuthor;

  /// The policy applied to the operations the server refused.
  final RetryPolicy retryPolicy;

  /// The real-time relay, `null` when the build follows no relay.
  ///
  /// The relay is optional: an application that does not configure it keeps
  /// the manual synchronisation, and everything else works the same.
  final RealTimeTransport? realTime;

  final StreamController<SyncStatus> _statuses =
      StreamController<SyncStatus>.broadcast();

  final StreamController<SyncEvent> _events =
      StreamController<SyncEvent>.broadcast();

  final Map<String, _Follower> _followers = <String, _Follower>{};

  StreamSubscription<RejectedOperation>? _refusals;

  SyncStatus _status = SyncStatus.offline;

  bool _isRunning = false;

  /// The resynchronization of the documents with the server.
  late final SyncResynchronizer _resynchronizer = SyncResynchronizer(
    database: database,
    transport: transport,
    author: _currentAuthor,
  );

  @override
  SyncStatus get status => _status;

  @override
  Stream<SyncStatus> watch() => _statuses.stream;

  /// The events of the synchronisation: the resynchronizations, the refusals
  /// of the server.
  @override
  Stream<SyncEvent> watchEvents() => _events.stream;

  @override
  Future<void> synchronize() async {
    if (_isRunning) return;
    _isRunning = true;
    try {
      await _synchronizeRound();
    } finally {
      _isRunning = false;
    }
  }

  /// Runs one synchronisation round.
  Future<void> _synchronizeRound() async {
    _emit(SyncStatus.syncing);
    var hasFailure = false;
    var hasConflict = false;
    _resynchronizer.forgetTrees();
    try {
      final List<DocumentBinding> bindings = await database.manuscripts
          .listDocumentBindings(_currentAuthor().value);
      for (final DocumentBinding binding in bindings) {
        final _RoundOutcome outcome = await _synchronize(binding);
        if (outcome == _RoundOutcome.failed) hasFailure = true;
        if (outcome == _RoundOutcome.conflict) hasConflict = true;
      }
      if (await _registerTheBooksWithoutScene(bindings)) {
        hasFailure = true;
      }
    } on ApiUnauthorizedException {
      // Le serveur a refusé la preuve du second facteur : l'auteur doit la
      // prouver à nouveau. L'erreur remonte — c'est la seule que
      // l'application peut réparer en lui demandant un code.
      _emit(SyncStatus.offline);
      rethrow;
    } on Object {
      hasFailure = true;
    }
    if (hasConflict) {
      _emit(SyncStatus.conflict);
      return;
    }
    _emit(hasFailure ? SyncStatus.offline : SyncStatus.synced);
  }

  @override
  Stream<RealTimeEvent> follow(String docId) {
    final RealTimeTransport? relay = realTime;
    if (relay == null) return const Stream<RealTimeEvent>.empty();
    final _Follower follower = _followers.putIfAbsent(
      docId,
      () => _Follower(documentId: docId, relay: relay, owner: this),
    );
    follower.count++;
    return follower.events.stream;
  }

  @override
  Future<void> release(String docId) async {
    final _Follower? follower = _followers[docId];
    if (follower == null) return;
    follower.count--;
    if (follower.count > 0) return;
    _followers.remove(docId);
    await follower.close();
    await realTime?.release(docId);
  }

  @override
  Future<void> publishCursor(String docId, PresenceCursor cursor) async {
    await realTime?.publishCursor(docId, cursor);
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
      _currentAuthor().value,
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
  Future<void> dispose() async {
    for (final _Follower follower in _followers.values) {
      await follower.close();
    }
    _followers.clear();
    await _refusals?.cancel();
    await realTime?.dispose();
    await _statuses.close();
    await _events.close();
  }

  /// Synchronises one document, and reports how the round went.
  ///
  /// The document is synchronised twice at the most: when the server refuses
  /// the version of the protocol of the client, the document is
  /// resynchronised and the synchronisation is retried once.
  Future<_RoundOutcome> _synchronize(DocumentBinding binding) async {
    final _RoundOutcome outcome = await _pushAndPull(binding.documentId);
    if (outcome != _RoundOutcome.schemaRefused) return outcome;
    return _resynchronize(binding);
  }

  /// Pushes the operations of the document and pulls the remote ones.
  ///
  /// The queue and the snapshots are read through the account of the
  /// session: the operations and the CRDT journal of another account stay
  /// on the device.
  Future<_RoundOutcome> _pushAndPull(String documentId) async {
    final AccountOpQueueStore queue = database.queueFor(
      () => _currentAuthor().value,
    );
    final DocumentOpQueueStore store = DocumentOpQueueStore(
      delegate: queue,
      documentId: documentId,
    );
    final SyncClient client = SyncClient(
      documentId: DocumentId(documentId),
      authorId: _currentAuthor(),
      transport: transport,
      queueStore: store,
      snapshotStore: database.snapshotsFor(() => _currentAuthor().value),
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
    } on Object catch (error) {
      final ApiUnauthorizedException? refusal = _refusalOf(error);
      if (refusal != null) {
        Error.throwWithStackTrace(refusal, StackTrace.current);
      }
      if (_isSchemaRefusal(error)) return _RoundOutcome.schemaRefused;
      return _RoundOutcome.failed;
    } finally {
      await client.dispose();
    }
  }

  /// Resynchronises the document of [binding] with the server.
  ///
  /// The server refused the version of the protocol of the client: the
  /// client pulls the tree of the project, replaces its local state by the
  /// one of the server, replays the operations the server has not accepted
  /// yet and retries the synchronisation **once**.
  ///
  /// A server that refuses again does not loop: the operations stay in the
  /// durable queue and the round ends.
  Future<_RoundOutcome> _resynchronize(DocumentBinding binding) async {
    if (_treeTransport == null) return _RoundOutcome.failed;
    final String documentId = binding.documentId;
    final String projectId = binding.projectId;

    _publishEvent(
      SyncResynchronizing(documentId: documentId, projectId: projectId),
    );
    // L'interface voit une synchronisation qui recommence, jamais une
    // erreur : l'auteur n'a rien a faire.
    _emit(SyncStatus.syncing);
    try {
      final ResynchronizationReport report = await _resynchronizer
          .resynchronize(documentId: documentId, projectId: projectId);
      _publishEvent(
        SyncResynchronized(
          documentId: documentId,
          replacedDocuments: report.replacedDocuments,
          replayedOperations: report.replayedOperations,
        ),
      );
    } on Object {
      return _RoundOutcome.failed;
    }
    // Le nouvel essai : **un seul**. Un serveur qui refuse encore laisse
    // les operations dans la file, et l'application ne boucle pas.
    final _RoundOutcome outcome = await _pushAndPull(documentId);
    if (outcome == _RoundOutcome.schemaRefused) return _RoundOutcome.failed;
    return outcome;
  }

  /// The transport that can pull the tree of a project, `null` when it
  /// cannot.
  TreeFetchingTransport? get _treeTransport {
    final SyncTransport current = transport;
    return current is TreeFetchingTransport ? current : null;
  }

  /// Whether [error] carries the refusal of the protocol version of the
  /// client.
  ///
  /// The client of the synchronisation wraps the errors it does not know:
  /// the cause of the transport error carries the refusal of the server.
  static bool _isSchemaRefusal(Object error) {
    if (error is SchemaVersionUnsupportedException) return true;
    if (error is SyncTransportException) {
      final Object? cause = error.cause;
      if (cause is SchemaVersionUnsupportedException) return true;
    }
    return false;
  }

  /// The refusal of the second factor carried by [error], `null` when the
  /// failure is another one.
  ///
  /// The client of the synchronisation wraps the errors it does not know:
  /// the cause of the transport error carries the refusal of the server.
  static ApiUnauthorizedException? _refusalOf(Object error) {
    if (error is ApiUnauthorizedException) return error;
    if (error is SyncTransportException) {
      final Object? cause = error.cause;
      if (cause is ApiUnauthorizedException) return cause;
    }
    return null;
  }

  /// Publishes a new status.
  void _emit(SyncStatus status) {
    if (_statuses.isClosed) return;
    _status = status;
    _statuses.add(status);
  }

  /// Publishes an event of the synchronisation.
  void _publishEvent(SyncEvent event) {
    if (_events.isClosed) return;
    _events.add(event);
  }

  /// Publishes the refusal of an operation by the server.
  ///
  /// The refusal is never swallowed: the operation stays in the durable
  /// queue of the device, and the application is told about it.
  void _publishRefusal(RejectedOperation refusal) {
    _publishEvent(
      SyncRefused(
        operationKey: refusal.operationKey,
        code: refusal.code,
        message: refusal.message,
      ),
    );
  }

  /// The stream of the events of the relay for the document [docId].
  ///
  /// The stream opens the channel of the document the first time somebody
  /// watches it, and closes it when the last watcher leaves.
  ///
  /// Applies what the relay brought, then publishes it.
  ///
  /// The operations are written to the durable journal **before** the event
  /// is published: the application reads the document when it receives the
  /// event, and it finds the text of the other author.
  Future<void> _publish(
    RealTimeEvent event,
    StreamController<RealTimeEvent> controller,
  ) async {
    if (event is RealTimeOperations) {
      await _applyRemoteOperations(event.operations);
    }
    if (event is RealTimeConnection && event.isConnected) {
      // Le canal vient de s'ouvrir : la file REST rattrape ce qui a été
      // manqué pendant la coupure.
      unawaited(synchronize());
    }
    if (!controller.isClosed) controller.add(event);
  }

  /// Writes the operations the relay delivered to the journal of the device.
  ///
  /// The operations are **not** queued for the server: the server stamps
  /// every push with the account of the caller, and pushing an operation of
  /// another author back would forge its authorship. The relay already
  /// delivered it, and the journal of the device is the durable trace.
  ///
  /// The CRDT is idempotent: an operation already known is ignored, so the
  /// same operation delivered twice never changes the document twice.
  Future<void> _applyRemoteOperations(List<SyncOp> operations) async {
    if (operations.isEmpty) return;
    final Map<String, List<SyncOp>> byDocument = <String, List<SyncOp>>{};
    for (final SyncOp operation in operations) {
      byDocument
          .putIfAbsent(operation.doc.value, () => <SyncOp>[])
          .add(operation);
    }
    final AccountSnapshotStore snapshots = database.snapshotsFor(
      () => _currentAuthor().value,
    );
    for (final MapEntry<String, List<SyncOp>> entry in byDocument.entries) {
      await _applyToDocument(snapshots, entry.key, entry.value);
    }
  }

  /// Applies the operations of a document to its journal.
  Future<void> _applyToDocument(
    AccountSnapshotStore snapshots,
    String documentId,
    List<SyncOp> operations,
  ) async {
    final DocumentId id = DocumentId(documentId);
    final DocumentSnapshot? snapshot = await snapshots.read(id);
    // Les operations deja connues sont celles du journal et celles que
    // l'etat compacte a deja appliquees : une operation livree deux fois
    // ne revient jamais dans le journal.
    final Set<String> known = snapshot == null
        ? <String>{}
        : snapshot.knownOperationKeys;
    final List<SyncOp> fresh = operations
        .where((SyncOp operation) => !known.contains(operation.operationKey))
        .toList(growable: false);
    if (fresh.isEmpty) return;

    final List<SyncOp> journal = snapshot == null
        ? fresh
        : <SyncOp>[...snapshot.operations, ...fresh];
    await snapshots.write(
      DocumentSnapshot(
        documentId: id,
        since: snapshot?.since ?? 0,
        maxLamport: _highestLamport(snapshot, journal),
        operations: journal,
        // L'etat compacte est conserve : il porte les operations que le
        // journal a purgees.
        state: snapshot?.state,
      ),
    );
  }

  /// The highest Lamport timestamp of the journal, the state included.
  static int _highestLamport(DocumentSnapshot? snapshot, List<SyncOp> journal) {
    final int known = snapshot?.maxLamport ?? 0;
    final int inJournal = _maxLamport(journal);
    return inJournal > known ? inJournal : known;
  }

  /// The highest Lamport timestamp of a journal.
  static int _maxLamport(List<SyncOp> journal) {
    var max = 0;
    for (final SyncOp operation in journal) {
      if (operation.lamport > max) max = operation.lamport;
    }
    return max;
  }
}

/// A document followed by the relay.
///
/// The follower opens the channel of the document when somebody watches it,
/// and closes it when the last watcher leaves. The count of the watchers
/// keeps the channel open as long as somebody needs it.
final class _Follower {
  _Follower({
    required this.documentId,
    required this.relay,
    required this.owner,
  });

  /// The document followed by the relay.
  final String documentId;

  /// The transport that opens the channel.
  final RealTimeTransport relay;

  /// The repository that applies the operations.
  final LocalSyncRepository owner;

  /// The number of watchers of the document.
  int count = 0;

  StreamSubscription<RealTimeEvent>? _subscription;

  /// The events published to the watchers.
  late final StreamController<RealTimeEvent> events =
      StreamController<RealTimeEvent>.broadcast(
        onListen: () {
          _subscription = relay.watch(documentId).listen((RealTimeEvent event) {
            unawaited(owner._publish(event, events));
          });
        },
        onCancel: () async {
          await _subscription?.cancel();
          _subscription = null;
        },
      );

  /// Closes the follower and releases the channel.
  Future<void> close() => events.close();
}

/// The outcome of a synchronisation round.
enum _RoundOutcome {
  /// The document is synchronised with the server.
  synced,

  /// The server could not be reached, or refused the operations.
  failed,

  /// The document holds a divergence the author must arbitrate.
  conflict,

  /// The server refused the version of the protocol of the client.
  ///
  /// The document is resynchronised before the round ends.
  schemaRefused,
}
