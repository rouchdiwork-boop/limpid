import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:limpid_app/src/data/app_database.dart';
import 'package:limpid_app/src/data/real_time_transport.dart';
import 'package:limpid_app/src/domain/realtime.dart';
import 'package:limpid_core/limpid_core.dart' hide SyncTransport;
import 'package:limpid_sync/limpid_sync.dart';

import 'fake_relay.dart';
import 'support.dart';

void main() {
  late AppDatabase database;
  late List<FakeRelayChannel> channels;
  late RealTimeTransport transport;

  setUp(() async {
    database = await openMemoryDatabase();
    channels = <FakeRelayChannel>[];
    transport = RealTimeTransport(
      baseUrl: Uri.parse('https://api.test'),
      store: database.manuscripts,
      rest: _RestTransport(),
      reconnectDelay: const Duration(milliseconds: 20),
      maxReconnectDelay: const Duration(milliseconds: 60),
      channelFactory: (String docId) {
        final FakeRelayChannel channel = FakeRelayChannel(docId);
        channels.add(channel);
        return channel;
      },
    );
  });

  tearDown(() async {
    await transport.dispose();
    await database.close();
  });

  test('the operations of the relay are published', () async {
    final List<RealTimeEvent> events = <RealTimeEvent>[];
    final StreamSubscription<RealTimeEvent> subscription = transport
        .watch('document-1')
        .listen(events.add);
    addTearDown(subscription.cancel);
    await _pump();

    channels.single.emitOperations(<SyncOp>[
      insertBlockOp(documentId: 'document-1'),
    ]);
    await _pump();

    final RealTimeOperations received = events
        .whereType<RealTimeOperations>()
        .single;
    expect(received.docId, 'document-1');
    expect(received.operations, hasLength(1));
  });

  test('the presence of the relay is published', () async {
    final List<RealTimeEvent> events = <RealTimeEvent>[];
    final StreamSubscription<RealTimeEvent> subscription = transport
        .watch('document-1')
        .listen(events.add);
    addTearDown(subscription.cancel);
    await _pump();

    channels.single.emitPresence(
      const PresencePeer(
        docId: 'document-1',
        userId: 'auteur-2',
        state: PresenceState.joined,
      ),
    );
    await _pump();

    final RealTimePresence received = events
        .whereType<RealTimePresence>()
        .single;
    expect(received.peer.userId, 'auteur-2');
    expect(received.peer.state, PresenceState.joined);
  });

  test('the channel is opened again after a closure', () async {
    final List<RealTimeEvent> events = <RealTimeEvent>[];
    final StreamSubscription<RealTimeEvent> subscription = transport
        .watch('document-1')
        .listen(events.add);
    addTearDown(subscription.cancel);
    await _pump();

    channels.single.emitConnected();
    await _pump();
    expect(events.whereType<RealTimeConnection>().single.isConnected, isTrue);

    await channels.single.close();
    await _pump(const Duration(milliseconds: 120));

    expect(channels, hasLength(2));
    expect(
      events.whereType<RealTimeConnection>().map(
        (RealTimeConnection event) => event.isConnected,
      ),
      containsAllInOrder(<bool>[true, false]),
    );
  });

  test('the cursor of the author reaches the relay', () async {
    final StreamSubscription<RealTimeEvent> subscription = transport
        .watch('document-1')
        .listen((_) {});
    addTearDown(subscription.cancel);
    await _pump();

    await transport.publishCursor(
      'document-1',
      const PresenceCursor(blockId: 'block-1', offset: 4),
    );

    expect(channels.single.cursors, hasLength(1));
    expect(channels.single.cursors.single.blockId, 'block-1');
    expect(channels.single.cursors.single.offset, 4);
  });

  test('a document nobody follows has no channel', () async {
    await transport.publishCursor(
      'document-2',
      const PresenceCursor(blockId: 'block-1', offset: 4),
    );

    expect(channels, isEmpty);
  });
}

/// A REST transport that answers nothing.
final class _RestTransport implements SyncTransport {
  @override
  Future<PushResult> push(List<SyncOp> ops) async => PushResult.empty;

  @override
  Future<List<SyncOp>> pull({
    required String docId,
    required int since,
    int limit = defaultPullLimit,
  }) async => const <SyncOp>[];

  @override
  Stream<TransportEvent> connect(String docId) =>
      const Stream<TransportEvent>.empty();

  @override
  Future<void> dispose() async {}
}

/// Lets the pending microtasks and timers run.
Future<void> _pump([Duration delay = const Duration(milliseconds: 20)]) async {
  await Future<void>.delayed(delay);
}
