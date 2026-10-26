import 'dart:math' as math;

import 'package:limpid_core/src/domain/content.dart';
import 'package:limpid_core/src/domain/enums.dart';
import 'package:limpid_core/src/domain/ids.dart';
import 'package:limpid_core/src/domain/mark.dart';
import 'package:limpid_core/src/errors.dart';
import 'package:limpid_core/src/sync/crdt_document.dart';
import 'package:limpid_core/src/sync/lamport_clock.dart';
import 'package:limpid_core/src/sync/ops.dart';
import 'package:limpid_core/src/sync/order_key.dart';
import 'package:limpid_core/src/sync/ulid.dart';

/// The transport exchanging operations with the server.
///
/// The API contract is `POST /v1/projects/:id/ops` and
/// `GET /v1/projects/:id/ops?since=`.
abstract interface class SyncTransport {
  /// Pushes [operations] and returns the operations the server accepted.
  Future<List<SyncOp>> push(List<SyncOp> operations);

  /// Pulls the operations that are more recent than [since].
  Future<List<SyncOp>> pull({required int since});
}

/// The result of a synchronisation round trip.
final class SyncReport {
  /// Creates a sync report.
  const SyncReport({
    required this.pushed,
    required this.pulled,
    required this.applied,
    required this.duplicates,
  });

  /// Number of operations pushed to the server.
  final int pushed;

  /// Number of operations received from the server.
  final int pulled;

  /// Number of operations that changed the document.
  final int applied;

  /// Number of operations that were already known.
  final int duplicates;

  @override
  String toString() =>
      'SyncReport(pushed: $pushed, pulled: $pulled, '
      'applied: $applied, duplicates: $duplicates)';
}

/// The outcome of a synchronisation round trip.
final class SyncResult {
  /// Creates a sync result.
  const SyncResult({required this.engine, required this.report});

  /// The engine after the round trip.
  final SyncEngine engine;

  /// The statistics of the round trip.
  final SyncReport report;
}

/// Orchestrates the offline operation log of a document.
///
/// The engine is immutable: every method returns a new engine, so the state
/// can be snapshotted, stored and replayed safely.
final class SyncEngine {
  /// Creates a sync engine.
  SyncEngine({
    required this.documentId,
    required this.authorId,
    CrdtDocument? document,
    List<SyncOp>? pendingOperations,
    LamportClock? clock,
    this.transport,
    UlidGenerator? ulidGenerator,
    this.lastPulledLamport = 0,
  }) : document = document ?? CrdtDocument.empty(documentId),
       _pending = List<SyncOp>.unmodifiable(
         pendingOperations ?? const <SyncOp>[],
       ),
       _clock = clock ?? const LamportClock(),
       _ulid = ulidGenerator ?? UlidGenerator();

  /// The document synchronised by this engine.
  final CrdtDocument document;

  /// The document identifier.
  final DocumentId documentId;

  /// The author of the local operations.
  final AuthorId authorId;

  /// The transport used to reach the server, `null` when offline.
  final SyncTransport? transport;

  /// The highest Lamport timestamp pulled from the server.
  final int lastPulledLamport;

  final List<SyncOp> _pending;
  final LamportClock _clock;
  final UlidGenerator _ulid;

  /// The operations waiting to be pushed to the server.
  List<SyncOp> get pendingOperations => _pending;

  /// The logical clock of the engine.
  LamportClock get clock => _clock;

  /// Whether there are operations waiting to be pushed.
  bool get hasPendingOperations => _pending.isNotEmpty;

  /// Generates a new identifier for a local entity.
  Id<T> nextId<T extends IdTag>() => Id<T>(_ulid.generate().value);

  /// Creates a block in the document.
  SyncEngine insertBlock({
    required BlockId blockId,
    BlockId? parent,
    required OrderKey order,
    required BlockType type,
    required BlockContent content,
  }) {
    final tick = _clock.tick();
    final op = InsertBlockOp(
      doc: documentId,
      lamport: tick.current,
      author: authorId,
      blockId: blockId,
      parent: parent,
      order: order,
      type: type,
      content: content,
    );
    return _commit(op, tick);
  }

  /// Updates the content of a block.
  SyncEngine updateContent({
    required BlockId blockId,
    required BlockContent content,
  }) {
    final tick = _clock.tick();
    final latest = document.latestContentVersion(blockId);
    final op = UpdateContentOp(
      doc: documentId,
      lamport: tick.current,
      author: authorId,
      blockId: blockId,
      content: content,
      base: latest == null ? null : ContentBase(version: latest),
    );
    return _commit(op, tick);
  }

  /// Deletes a block (reversible tombstone).
  SyncEngine deleteBlock({required BlockId blockId}) {
    final tick = _clock.tick();
    final op = DeleteBlockOp(
      doc: documentId,
      lamport: tick.current,
      author: authorId,
      blockId: blockId,
    );
    return _commit(op, tick);
  }

  /// Moves a block to another position.
  SyncEngine moveBlock({
    required BlockId blockId,
    BlockId? parent,
    required OrderKey order,
  }) {
    final tick = _clock.tick();
    final op = MoveBlockOp(
      doc: documentId,
      lamport: tick.current,
      author: authorId,
      blockId: blockId,
      parent: parent,
      order: order,
    );
    return _commit(op, tick);
  }

  /// Sets a scalar metadata of the document.
  SyncEngine setMeta({required String key, required String value}) {
    final tick = _clock.tick();
    final op = SetMetaOp(
      doc: documentId,
      lamport: tick.current,
      author: authorId,
      key: key,
      value: value,
    );
    return _commit(op, tick);
  }

  /// Adds a mark on a block.
  SyncEngine addMark({
    required MarkId markId,
    required BlockId blockId,
    required MarkType type,
    required MarkRange range,
    String body = '',
  }) {
    final tick = _clock.tick();
    final op = AddMarkOp(
      doc: documentId,
      lamport: tick.current,
      author: authorId,
      markId: markId,
      blockId: blockId,
      type: type,
      range: range,
      body: body,
    );
    return _commit(op, tick);
  }

  /// Removes a mark from a block.
  SyncEngine removeMark({required MarkId markId, required BlockId blockId}) {
    final tick = _clock.tick();
    final op = RemoveMarkOp(
      doc: documentId,
      lamport: tick.current,
      author: authorId,
      markId: markId,
      blockId: blockId,
    );
    return _commit(op, tick);
  }

  /// Applies an operation received from the server.
  ///
  /// The operation is ignored when it was already applied: the engine is
  /// idempotent by `(doc, lamport, author)`.
  SyncEngine applyRemote(SyncOp op) {
    if (document.hasApplied(op)) return this;
    final clock = _clock.receive(op.lamport);
    final updated = document.apply(op);
    return SyncEngine(
      documentId: documentId,
      authorId: authorId,
      document: updated,
      pendingOperations: _pending,
      clock: clock,
      transport: transport,
      ulidGenerator: _ulid,
      lastPulledLamport: math.max(lastPulledLamport, op.lamport),
    );
  }

  /// Pushes the pending operations, pulls the remote ones and merges them.
  ///
  /// Throws an [InvalidSyncOperationException] when no transport is
  /// configured.
  Future<SyncResult> sync() async {
    final activeTransport = transport;
    if (activeTransport == null) {
      throw const InvalidSyncOperationException(
        'No transport is configured on this sync engine.',
      );
    }
    final accepted = await activeTransport.push(_pending);
    final pulled = await activeTransport.pull(since: lastPulledLamport);
    var engine = this;
    var applied = 0;
    var duplicates = 0;
    for (final op in <SyncOp>[...accepted, ...pulled]) {
      if (engine.document.hasApplied(op)) {
        duplicates++;
        continue;
      }
      engine = engine.applyRemote(op);
      applied++;
    }
    final report = SyncReport(
      pushed: _pending.length,
      pulled: pulled.length,
      applied: applied,
      duplicates: duplicates,
    );
    return SyncResult(
      engine: engine.copyWith(pendingOperations: const <SyncOp>[]),
      report: report,
    );
  }

  /// Returns a copy of this engine with the given fields replaced.
  SyncEngine copyWith({
    CrdtDocument? document,
    List<SyncOp>? pendingOperations,
    LamportClock? clock,
    int? lastPulledLamport,
  }) {
    return SyncEngine(
      documentId: documentId,
      authorId: authorId,
      document: document ?? this.document,
      pendingOperations: pendingOperations ?? _pending,
      clock: clock ?? _clock,
      transport: transport,
      ulidGenerator: _ulid,
      lastPulledLamport: lastPulledLamport ?? this.lastPulledLamport,
    );
  }

  SyncEngine _commit(SyncOp op, LamportClock clock) {
    return SyncEngine(
      documentId: documentId,
      authorId: authorId,
      document: document.apply(op),
      pendingOperations: <SyncOp>[..._pending, op],
      clock: clock,
      transport: transport,
      ulidGenerator: _ulid,
      lastPulledLamport: lastPulledLamport,
    );
  }
}
