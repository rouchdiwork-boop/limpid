import 'dart:async';

import 'package:limpid_core/limpid_core.dart' hide SyncTransport;
import 'package:limpid_sync/src/conflict.dart';
import 'package:limpid_sync/src/conflict_detector.dart';
import 'package:limpid_sync/src/errors.dart';
import 'package:limpid_sync/src/network_status.dart';
import 'package:limpid_sync/src/queue/op_queue.dart';
import 'package:limpid_sync/src/queue/op_queue_store.dart';
import 'package:limpid_sync/src/queue/queued_op.dart';
import 'package:limpid_sync/src/snapshot_store.dart';
import 'package:limpid_sync/src/sync_events.dart';
import 'package:limpid_sync/src/sync_state.dart';
import 'package:limpid_sync/src/transport/sync_transport.dart';

/// The statistics of a synchronisation round trip.
final class SyncRoundReport {
  /// Creates a report.
  const SyncRoundReport({
    this.pushed = 0,
    this.pulled = 0,
    this.applied = 0,
    this.duplicates = 0,
    this.conflicts = const <ConflictReport>[],
    this.pending = 0,
  });

  /// The number of operations sent to the API.
  final int pushed;

  /// The number of operations received from the API.
  final int pulled;

  /// The number of operations that changed the document.
  final int applied;

  /// The number of operations that were already known.
  final int duplicates;

  /// The divergences detected during the round trip.
  final List<ConflictReport> conflicts;

  /// The number of operations still waiting in the local queue.
  final int pending;

  @override
  String toString() =>
      'SyncRoundReport(pushed: $pushed, pulled: $pulled, applied: $applied, '
      'duplicates: $duplicates, pending: $pending)';
}

/// The orchestrator of the synchronisation of a document.
///
/// The client owns the four pieces of the offline-first promise:
/// the CRDT document, the persistent queue, the cursor of the API and the
/// events published to the application.
///
/// ## Offline contract
///
/// [enqueue] never throws because of the network: the operation is persisted
/// first, then the client tries to send it. When the API cannot be reached
/// the state switches to [SyncStatus.offline] and the queue keeps growing.
///
/// [sync] follows the same rule for the connectivity failures: it switches
/// to [SyncStatus.offline] and returns an empty report. The other failures
/// — authentication, server errors, conflicts — are *not* swallowed: they
/// are published on the event stream, recorded in the state and rethrown, so
/// the application can react to them.
final class SyncClient {
  /// Creates a client for [documentId].
  SyncClient({
    required this.documentId,
    required this.authorId,
    required this.transport,
    required OpQueueStore queueStore,
    required this.snapshotStore,
    OpQueue? queue,
    this.connectivity,
    this.conflictDetector = const ConflictDetector(),
    DateTime Function()? now,
    this.pullLimit = defaultPullLimit,
    this.failOnConflict = false,
  }) : queue = queue ?? OpQueue(store: queueStore),
       _document = CrdtDocument.empty(documentId),
       _now = now ?? DateTime.now;

  /// The document synchronised by the client.
  final DocumentId documentId;

  /// The author of the local operations.
  final AuthorId authorId;

  /// The transport used to reach the API.
  final SyncTransport transport;

  /// The persistent queue of the operations waiting to be sent.
  final OpQueue queue;

  /// The persistence of the local snapshots.
  final SnapshotStore snapshotStore;

  /// The connectivity probe, `null` when the client always assumes the API
  /// is reachable and lets the transport report the failures.
  final ConnectivityProbe? connectivity;

  /// The detector of the divergences between the local and the remote
  /// versions.
  final ConflictDetector conflictDetector;

  /// The maximum number of operations requested by a single pull.
  final int pullLimit;

  /// Whether [sync] throws a [SyncConflictException] when it detects a
  /// divergence.
  ///
  /// The default is `false`: the divergence is published on the event stream
  /// and the author arbitrates it, the synchronisation itself succeeds. An
  /// application that prefers to stop on a divergence sets it to `true`.
  final bool failOnConflict;

  final DateTime Function() _now;
  final StreamController<SyncEvent> _events =
      StreamController<SyncEvent>.broadcast();

  CrdtDocument _document;
  List<SyncOp> _journal = const <SyncOp>[];
  Set<String> _appliedKeys = <String>{};
  List<SyncOp> _localOperations = const <SyncOp>[];
  int _since = 0;
  int _maxLamport = 0;
  bool _isOnline = true;
  SyncState _state = const SyncState();
  Future<void>? _restoration;

  /// The CRDT document as it is known locally.
  CrdtDocument get document => _document;

  /// The current state of the client.
  SyncState get state => _state;

  /// The number of operations waiting to be sent to the API.
  int get pendingCount => _state.pendingCount;

  /// The cursor of the last operation pulled from the API.
  int get since => _since;

  /// The highest Lamport timestamp observed for the document.
  int get maxLamport => _maxLamport;

  /// The events published by the client.
  ///
  /// The events of [docId] are filtered, so a client can watch several
  /// documents without mixing their streams.
  Stream<SyncEvent> watch(String docId) {
    return _events.stream.where((event) => event.documentId.value == docId);
  }

  /// Restores the document, the cursor and the queue from the local storage.
  ///
  /// The call is idempotent and is automatically awaited by [enqueue] and
  /// [sync]; the application only needs it when it wants to read [document]
  /// before the first synchronisation.
  Future<void> restore() => _restoration ??= _restore();

  /// Persists [op] locally and tries to send it immediately.
  ///
  /// The operation is written to the queue **before** any network call, so
  /// a crash between the two cannot lose it. Calling [enqueue] twice with
  /// the same operation is a no-op: the deduplication key of the CRDT is
  /// `(doc_id, lamport, author_id)`.
  ///
  /// The call never throws because of the network: the errors are published
  /// on the event stream and recorded in the state.
  Future<void> enqueue(SyncOp op) async {
    await restore();
    _checkDocument(op);
    if (_appliedKeys.contains(op.operationKey)) return;
    await queue.enqueue(op);
    _apply(op, remote: false);
    await _persist();
    await _refreshPendingCount();
    await _flushIfOnline();
  }

  /// Applies the resolution chosen by the author and enqueues the result.
  ///
  /// The resolution is applied to the content of the block: the local
  /// version, the remote version or the 3-way merge of the two.
  ///
  /// [lamport] is the timestamp of the new operation. The caller owns the
  /// Lamport clock of the application, exactly as for every other operation
  /// it produces.
  Future<void> enqueueConflictResolution(
    ConflictReport report,
    ConflictResolution resolution, {
    required int lamport,
  }) async {
    final content = const ConflictResolver().resolve(report, resolution);
    await enqueue(
      UpdateContentOp(
        doc: report.documentId,
        lamport: lamport,
        author: authorId,
        blockId: report.blockId,
        content: content,
      ),
    );
  }

  /// Runs a synchronisation round trip for [docId].
  ///
  /// The queued operations are sent first, then the remote operations are
  /// pulled from the cursor and applied to the document.
  ///
  /// Throws a [SyncAuthException] when the API rejects the credentials, and
  /// a [SyncTransportException] when the API answers an error the client
  /// cannot fix. A connectivity failure never throws: the state switches to
  /// [SyncStatus.offline] instead.
  Future<SyncRoundReport> sync(String docId) async {
    await restore();
    _checkDocId(docId);
    _setState(_state.copyWith(status: SyncStatus.syncing, clearError: true));
    try {
      if (!await _checkConnectivity()) {
        await _refreshPendingCount();
        return SyncRoundReport(pending: _state.pendingCount);
      }
      final pushed = await _flush();
      final pulled = await _pull();
      final applied = _applyAll(pulled);
      final duplicates = pulled.length - applied;
      final conflicts = _detectConflicts(pulled);
      if (conflicts.isNotEmpty) {
        _events.add(SyncConflictDetected(documentId, conflicts));
        if (failOnConflict) {
          throw SyncConflictException(
            'The document contains divergent versions the author must '
            'arbitrate.',
            reports: conflicts,
          );
        }
      }
      await _persist();
      await _refreshPendingCount();
      _setState(
        _state.copyWith(
          status: SyncStatus.idle,
          lastSyncAt: _now(),
          clearError: true,
        ),
      );
      return SyncRoundReport(
        pushed: pushed,
        pulled: pulled.length,
        applied: applied,
        duplicates: duplicates,
        conflicts: conflicts,
        pending: _state.pendingCount,
      );
    } on SyncTransportException catch (error) {
      if (error.isNetworkFailure) {
        await _goOffline();
        return SyncRoundReport(pending: _state.pendingCount);
      }
      _fail(error);
      rethrow;
    } on SyncException catch (error) {
      _fail(error);
      rethrow;
    }
  }

  /// Releases the resources held by the client.
  Future<void> dispose() async {
    await _events.close();
    await transport.dispose();
  }

  Future<void> _restore() async {
    final snapshot = await snapshotStore.read(documentId);
    if (snapshot != null) {
      _document = snapshot.restore();
      _journal = List<SyncOp>.unmodifiable(snapshot.operations);
      _appliedKeys = snapshot.operations
          .map((operation) => operation.operationKey)
          .toSet();
      _since = snapshot.since;
      _maxLamport = snapshot.maxLamport;
    }
    final pending = await queue.pending();
    for (final entry in pending) {
      final op = entry.operation;
      if (op.doc != documentId) continue;
      if (_appliedKeys.contains(op.operationKey)) continue;
      _apply(op, remote: false);
    }
    await _refreshPendingCount();
  }

  /// Sends the ready operations and returns the number of acknowledged ones.
  Future<int> _flush() async {
    final ready = await queue.ready(limit: defaultPushBatchSize);
    if (ready.isEmpty) return 0;
    final PushResult result;
    try {
      result = await transport.push(
        ready.map((entry) => entry.operation).toList(growable: false),
      );
    } on SyncException catch (error) {
      await _markAllFailed(ready, error.message);
      rethrow;
    } on Object catch (error) {
      final failure = SyncTransportException(
        'The operation could not be sent: $error',
        code: 'sync_transport_error',
        cause: error,
      );
      await _markAllFailed(ready, failure.message);
      throw failure;
    }
    final acknowledged = result.acknowledged
        .map((operation) => operation.operationKey)
        .toSet();
    final rejected = result.rejected
        .map((operation) => operation.operationKey)
        .toSet();
    final sent = <QueuedOp>[];
    for (final entry in ready) {
      final key = entry.operationKey;
      if (acknowledged.contains(key)) {
        sent.add(entry);
        continue;
      }
      final reason = rejected.contains(key)
          ? 'The server refused the operation.'
          : 'The server did not acknowledge the operation.';
      await queue.markFailed(entry, reason: reason);
    }
    await queue.markSent(sent);
    await queue.purgeSent();
    for (final operation in result.acknowledged) {
      _apply(operation, remote: false);
    }
    return sent.length;
  }

  /// Marks every entry of [entries] as failed.
  Future<void> _markAllFailed(Iterable<QueuedOp> entries, String reason) async {
    for (final entry in entries) {
      await queue.markFailed(entry, reason: reason);
    }
  }

  /// Pulls the remote operations and advances the cursor.
  Future<List<SyncOp>> _pull() async {
    final operations = <SyncOp>[];
    var cursor = _since;
    while (true) {
      final batch = await transport.pull(
        docId: documentId.value,
        since: cursor,
        limit: pullLimit,
      );
      if (batch.isEmpty) break;
      operations.addAll(batch);
      cursor += batch.length;
      if (batch.length < pullLimit) break;
    }
    _since = cursor;
    return operations;
  }

  /// Applies the operations and returns the number of new ones.
  int _applyAll(List<SyncOp> operations) {
    var applied = 0;
    for (final operation in operations) {
      if (operation.doc != documentId) continue;
      if (_appliedKeys.contains(operation.operationKey)) continue;
      _apply(operation, remote: true);
      applied++;
    }
    return applied;
  }

  /// Applies [operation] to the document and publishes the event.
  ///
  /// The call is idempotent: an operation already known is ignored, so the
  /// journal never holds the same operation twice.
  void _apply(SyncOp operation, {required bool remote}) {
    if (_appliedKeys.contains(operation.operationKey)) return;
    _document = _document.apply(operation);
    _appliedKeys.add(operation.operationKey);
    _journal = List<SyncOp>.unmodifiable(<SyncOp>[..._journal, operation]);
    if (operation.lamport > _maxLamport) _maxLamport = operation.lamport;
    if (!remote) {
      _localOperations = List<SyncOp>.unmodifiable(<SyncOp>[
        ..._localOperations,
        operation,
      ]);
    }
    _events.add(
      remote
          ? SyncRemoteOpApplied(documentId, operation)
          : SyncLocalOpApplied(documentId, operation),
    );
  }

  /// Detects the divergences between the local and the remote versions.
  List<ConflictReport> _detectConflicts(List<SyncOp> remoteOperations) {
    if (remoteOperations.isEmpty) return const <ConflictReport>[];
    if (_localOperations.isEmpty) return const <ConflictReport>[];
    final localOperations = _localOperations;
    return conflictDetector.detect(
      document: _document,
      localOperations: localOperations,
      remoteOperations: remoteOperations,
      detectedAt: _now(),
    );
  }

  /// Sends the queue when the API is reachable.
  Future<void> _flushIfOnline() async {
    if (!await _checkConnectivity()) return;
    try {
      await _flush();
      await _persist();
    } on SyncException catch (error) {
      if (error is SyncTransportException && error.isNetworkFailure) {
        await _goOffline();
        return;
      }
      _fail(error);
    } on Object catch (error) {
      _fail(
        SyncTransportException(
          'The operation could not be sent: $error',
          code: 'sync_transport_error',
          cause: error,
        ),
      );
    }
  }

  /// Checks the connectivity and publishes the change.
  Future<bool> _checkConnectivity() async {
    final probe = connectivity;
    if (probe == null) return true;
    final online = await probe.isOnline();
    if (online != _isOnline) {
      _isOnline = online;
      _events.add(SyncNetworkStatusChanged(documentId, online));
      _setState(
        _state.copyWith(
          isOnline: online,
          status: online ? _state.status : SyncStatus.offline,
        ),
      );
    }
    return online;
  }

  /// Switches the client to the offline state.
  Future<void> _goOffline() async {
    _isOnline = false;
    _events.add(SyncNetworkStatusChanged(documentId, false));
    _setState(
      _state.copyWith(
        status: SyncStatus.offline,
        isOnline: false,
        clearError: true,
      ),
    );
    await _refreshPendingCount();
  }

  /// Records an error and publishes it.
  void _fail(SyncException error) {
    _events.add(SyncErrorRaised(documentId, error));
    _setState(_state.copyWith(status: SyncStatus.error, lastError: error));
  }

  /// Publishes a new state.
  void _setState(SyncState state) {
    _state = state;
    _events.add(SyncStateChanged(documentId, state));
  }

  /// Refreshes the number of operations waiting in the queue.
  Future<void> _refreshPendingCount() async {
    final count = await queue.pendingCount();
    if (count == _state.pendingCount) return;
    _setState(_state.copyWith(pendingCount: count));
  }

  /// Writes the local snapshot.
  Future<void> _persist() async {
    await snapshotStore.write(
      DocumentSnapshot(
        documentId: documentId,
        since: _since,
        maxLamport: _maxLamport,
        operations: _journal,
      ),
    );
  }

  /// Rejects the operations of another document.
  void _checkDocument(SyncOp operation) {
    if (operation.doc == documentId) return;
    throw SyncTransportException(
      'Operation ${operation.operationKey} targets document '
      '${operation.doc.value}, not ${documentId.value}.',
      code: 'sync_invalid_operation',
    );
  }

  /// Rejects a call made for another document.
  void _checkDocId(String docId) {
    if (docId == documentId.value) return;
    throw SyncTransportException(
      'This client synchronises the document ${documentId.value}, '
      'not $docId.',
      code: 'sync_invalid_operation',
    );
  }
}
