import 'dart:math' as math;

import 'package:limpid_core/limpid_core.dart' hide SyncTransport;
import 'package:limpid_sync/limpid_sync.dart';

/// A fake API holding the log of the operations of every document.
///
/// The server is the shared state of the convergence tests: it accepts the
/// pushed operations, deduplicates them and serves them back in a random
/// order, which is exactly the disorder the CRDT must absorb.
final class FakeSyncServer {
  /// Creates a server.
  FakeSyncServer({math.Random? random}) : _random = random ?? math.Random();

  final math.Random _random;
  final List<SyncOp> _log = <SyncOp>[];
  final Set<String> _keys = <String>{};

  /// Whether the server answers.
  bool isOnline = true;

  /// The number of pushes that must fail before the server answers again.
  int failingPushes = 0;

  /// The maximum delay applied to the answers, in milliseconds.
  int maxDelayMilliseconds = 3;

  /// The operations stored by the server, in arrival order.
  List<SyncOp> get log => List<SyncOp>.unmodifiable(_log);

  /// Accepts [ops] and returns what the server stored.
  Future<PushResult> push(List<SyncOp> ops) async {
    await _delay();
    if (failingPushes > 0) {
      failingPushes--;
      throw SyncTransportException(
        'The API is unreachable.',
        code: 'sync_unreachable',
        isNetworkFailure: true,
      );
    }
    if (!isOnline) {
      throw SyncTransportException(
        'The API is unreachable.',
        code: 'sync_unreachable',
        isNetworkFailure: true,
      );
    }
    final accepted = <SyncOp>[];
    final duplicated = <SyncOp>[];
    var lamportAck = 0;
    for (final op in ops) {
      if (op.lamport > lamportAck) lamportAck = op.lamport;
      if (_keys.contains(op.operationKey)) {
        duplicated.add(op);
        continue;
      }
      _keys.add(op.operationKey);
      _log.add(op);
      accepted.add(op);
    }
    return PushResult(
      accepted: accepted,
      duplicated: duplicated,
      rejected: const <RejectedOperation>[],
      lamportAck: lamportAck,
    );
  }

  /// Serves the operations of [docId] that follow the cursor [since].
  ///
  /// The batch is shuffled: the client must converge whatever the order of
  /// the delivery.
  Future<List<SyncOp>> pull({
    required String docId,
    required int since,
    int limit = defaultPullLimit,
  }) async {
    await _delay();
    if (!isOnline) {
      throw SyncTransportException(
        'The API is unreachable.',
        code: 'sync_unreachable',
        isNetworkFailure: true,
      );
    }
    final documentOps = _log
        .where((op) => op.doc.value == docId)
        .toList(growable: false);
    final batch = documentOps.skip(since).take(limit).toList();
    batch.shuffle(_random);
    return batch;
  }

  Future<void> _delay() async {
    if (maxDelayMilliseconds <= 0) return;
    final milliseconds = _random.nextInt(maxDelayMilliseconds + 1);
    if (milliseconds == 0) return;
    await Future<void>.delayed(Duration(milliseconds: milliseconds));
  }
}

/// A [SyncTransport] bound to a [FakeSyncServer].
final class FakeSyncTransport implements SyncTransport {
  /// Creates a transport talking to [server].
  FakeSyncTransport(this.server);

  /// The server the transport talks to.
  final FakeSyncServer server;

  /// The operations pushed by the transport, in order.
  final List<List<SyncOp>> pushes = <List<SyncOp>>[];

  @override
  Future<PushResult> push(List<SyncOp> ops) {
    pushes.add(List<SyncOp>.unmodifiable(ops));
    return server.push(ops);
  }

  @override
  Future<List<SyncOp>> pull({
    required String docId,
    required int since,
    int limit = defaultPullLimit,
  }) {
    return server.pull(docId: docId, since: since, limit: limit);
  }

  @override
  Stream<TransportEvent> connect(String docId) =>
      const Stream<TransportEvent>.empty();

  @override
  Future<void> dispose() async {}
}

/// A transport always failing like an unreachable network.
final class OfflineTransport implements SyncTransport {
  /// Creates an offline transport.
  OfflineTransport();

  /// The number of pushes received.
  int pushCount = 0;

  @override
  Future<PushResult> push(List<SyncOp> ops) async {
    pushCount++;
    throw SyncTransportException(
      'The API is unreachable.',
      code: 'sync_unreachable',
      isNetworkFailure: true,
    );
  }

  @override
  Future<List<SyncOp>> pull({
    required String docId,
    required int since,
    int limit = defaultPullLimit,
  }) async {
    throw SyncTransportException(
      'The API is unreachable.',
      code: 'sync_unreachable',
      isNetworkFailure: true,
    );
  }

  @override
  Stream<TransportEvent> connect(String docId) =>
      const Stream<TransportEvent>.empty();

  @override
  Future<void> dispose() async {}
}

/// A transport always answering with the same operations.
final class StaticTransport implements SyncTransport {
  /// Creates a transport serving [operations].
  StaticTransport(this.operations);

  /// The operations served by the transport.
  final List<SyncOp> operations;

  /// The number of pushes received.
  int pushCount = 0;

  @override
  Future<PushResult> push(List<SyncOp> ops) async {
    pushCount++;
    return PushResult(
      accepted: List<SyncOp>.unmodifiable(ops),
      duplicated: const <SyncOp>[],
      rejected: const <RejectedOperation>[],
      lamportAck: ops.isEmpty ? 0 : ops.last.lamport,
    );
  }

  @override
  Future<List<SyncOp>> pull({
    required String docId,
    required int since,
    int limit = defaultPullLimit,
  }) async {
    return List<SyncOp>.unmodifiable(operations);
  }

  @override
  Stream<TransportEvent> connect(String docId) =>
      const Stream<TransportEvent>.empty();

  @override
  Future<void> dispose() async {}
}

/// A connectivity probe with a fixed answer.
final class FixedConnectivityProbe implements ConnectivityProbe {
  /// Creates a probe answering [online].
  FixedConnectivityProbe(this.online);

  /// Whether the API is reachable.
  bool online;

  /// The number of calls received.
  int callCount = 0;

  @override
  Future<bool> isOnline() async {
    callCount++;
    return online;
  }
}
