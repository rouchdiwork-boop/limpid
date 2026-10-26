import 'dart:convert';

import 'package:limpid_core/limpid_core.dart' hide SyncTransport;
import 'package:limpid_sync/limpid_sync.dart';
import 'package:test/test.dart';

import '../support/fake_server.dart';
import '../support/fake_websocket.dart';

void main() {
  group('WebSocketSyncTransport', () {
    const doc = DocumentId('doc-ws');
    final operation = InsertBlockOp(
      doc: doc,
      lamport: 9,
      author: const AuthorId('author-b'),
      blockId: const BlockId('block-1'),
      parent: null,
      order: OrderKey.initial,
      type: BlockType.paragraph,
      content: const TextContent('Temps réel.'),
    );

    test('the operations received on the channel are published', () async {
      final channel = FakeWebSocketChannel();
      final transport = WebSocketSyncTransport(
        rest: StaticTransport(const <SyncOp>[]),
        connector: (uri, {protocols}) async => channel,
        baseUrl: Uri.parse('https://api.limpid.test'),
        projectIdResolver: (docId) async => 'project-1',
      );
      addTearDown(transport.dispose);
      final events = <TransportEvent>[];
      final subscription = transport.connect(doc.value).listen(events.add);
      addTearDown(() async {
        await channel.closeChannel();
        await subscription.cancel();
      });

      await _pump();
      expect(events.whereType<TransportConnected>(), hasLength(1));
      expect(channel.sent, hasLength(1));
      final join =
          jsonDecode(channel.sent.single! as String) as Map<String, Object?>;
      expect(join['type'], 'join');
      final payload = join['payload']! as Map<String, Object?>;
      expect(payload['doc_id'], doc.value);
      expect(payload['project_id'], 'project-1');

      channel.emitFrame('op', OpCodec.encode(operation));
      await _pump();

      final received = events.whereType<TransportOperationsReceived>().toList();
      expect(received, hasLength(1));
      expect(received.single.operations.single, operation);
    });

    test('the presence announced by the relay is published', () async {
      final channel = FakeWebSocketChannel();
      final transport = WebSocketSyncTransport(
        rest: StaticTransport(const <SyncOp>[]),
        connector: (uri, {protocols}) async => channel,
        baseUrl: Uri.parse('https://api.limpid.test'),
        projectIdResolver: (docId) async => 'project-1',
      );
      addTearDown(transport.dispose);
      final events = <TransportEvent>[];
      final subscription = transport.connect(doc.value).listen(events.add);
      addTearDown(() async {
        await channel.closeChannel();
        await subscription.cancel();
      });
      await _pump();

      channel.emitFrame('presence', <String, Object?>{
        'doc_id': doc.value,
        'user_id': 'author-b',
        'state': 'cursor',
        'cursor': <String, Object?>{'block_id': 'block-1', 'offset': 12},
      });
      await _pump();

      final received = events.whereType<TransportPresenceReceived>().toList();
      expect(received, hasLength(1));
      expect(received.single.peer.userId, 'author-b');
      expect(received.single.peer.state, PresenceState.cursor);
      expect(received.single.peer.cursor?.blockId, 'block-1');
      expect(received.single.peer.cursor?.offset, 12);
    });

    test('the cursor of the author is announced to the relay', () async {
      final channel = FakeWebSocketChannel();
      final transport = WebSocketSyncTransport(
        rest: StaticTransport(const <SyncOp>[]),
        connector: (uri, {protocols}) async => channel,
        baseUrl: Uri.parse('https://api.limpid.test'),
        projectIdResolver: (docId) async => 'project-1',
      );
      addTearDown(transport.dispose);
      final subscription = transport.connect(doc.value).listen((_) {});
      addTearDown(() async {
        await channel.closeChannel();
        await subscription.cancel();
      });
      await _pump();

      await transport.publishCursor(
        doc.value,
        const PresenceCursor(blockId: 'block-3', offset: 7),
      );
      await _pump();

      final frames = channel.sent
          .whereType<String>()
          .map((String frame) => jsonDecode(frame) as Map<String, Object?>)
          .toList(growable: false);
      final cursor = frames.lastWhere(
        (Map<String, Object?> frame) => frame['type'] == 'cursor',
      );
      final payload = cursor['payload']! as Map<String, Object?>;
      expect(payload['doc_id'], doc.value);
      expect(payload['project_id'], 'project-1');
      final position = payload['cursor']! as Map<String, Object?>;
      expect(position['block_id'], 'block-3');
      expect(position['offset'], 7);
    });

    test('the ping of the relay is answered', () async {
      final channel = FakeWebSocketChannel();
      final transport = WebSocketSyncTransport(
        rest: StaticTransport(const <SyncOp>[]),
        connector: (uri, {protocols}) async => channel,
        baseUrl: Uri.parse('https://api.limpid.test'),
        projectIdResolver: (docId) async => 'project-1',
      );
      addTearDown(transport.dispose);
      final subscription = transport.connect(doc.value).listen((_) {});
      addTearDown(() async {
        await channel.closeChannel();
        await subscription.cancel();
      });
      await _pump();

      channel.emitFrame('ping', <String, Object?>{});
      await _pump();

      final frames = channel.sent
          .whereType<String>()
          .map((String frame) => jsonDecode(frame) as Map<String, Object?>)
          .toList(growable: false);
      expect(
        frames.any((Map<String, Object?> frame) => frame['type'] == 'pong'),
        isTrue,
      );
    });

    test('a document of no known project is never joined', () async {
      final channel = FakeWebSocketChannel();
      final transport = WebSocketSyncTransport(
        rest: StaticTransport(const <SyncOp>[]),
        connector: (uri, {protocols}) async => channel,
        baseUrl: Uri.parse('https://api.limpid.test'),
        projectIdResolver: (docId) async => null,
      );
      addTearDown(transport.dispose);
      final events = <TransportEvent>[];
      final subscription = transport.connect(doc.value).listen(events.add);
      addTearDown(subscription.cancel);
      await _pump();

      expect(events.whereType<TransportConnected>(), isEmpty);
      expect(
        events.whereType<TransportFailure>().single.error.code,
        'sync_unknown_project',
      );
      expect(channel.sent, isEmpty);
    });

    test('an error frame is published as a failure', () async {
      final channel = FakeWebSocketChannel();
      final transport = WebSocketSyncTransport(
        rest: StaticTransport(const <SyncOp>[]),
        connector: (uri, {protocols}) async => channel,
        baseUrl: Uri.parse('https://api.limpid.test'),
        projectIdResolver: (docId) async => 'project-1',
      );
      addTearDown(transport.dispose);
      final events = <TransportEvent>[];
      final subscription = transport.connect(doc.value).listen(events.add);
      addTearDown(() async {
        await channel.closeChannel();
        await subscription.cancel();
      });
      await _pump();

      channel.emitFrame('error', <String, Object?>{
        'code': 'rate_limited',
        'message': 'Limite de débit dépassée.',
      });
      await _pump();

      final failures = events.whereType<TransportFailure>().toList();
      expect(failures, hasLength(1));
      expect(failures.single.error.code, 'rate_limited');
    });

    test('the channel is closed when the connection ends', () async {
      final channel = FakeWebSocketChannel();
      final transport = WebSocketSyncTransport(
        rest: StaticTransport(const <SyncOp>[]),
        connector: (uri, {protocols}) async => channel,
        baseUrl: Uri.parse('https://api.limpid.test'),
        projectIdResolver: (docId) async => 'project-1',
      );
      addTearDown(transport.dispose);
      final events = <TransportEvent>[];
      final subscription = transport.connect(doc.value).listen(events.add);
      addTearDown(() async {
        await channel.closeChannel();
        await subscription.cancel();
      });
      await _pump();

      await channel.closeChannel();
      await _pump();

      expect(events.whereType<TransportDisconnected>(), hasLength(1));
    });

    test('the push and the pull are delegated to the REST transport', () async {
      final rest = StaticTransport(<SyncOp>[operation]);
      final transport = WebSocketSyncTransport(
        rest: rest,
        connector: (uri, {protocols}) async => FakeWebSocketChannel(),
        baseUrl: Uri.parse('https://api.limpid.test'),
        projectIdResolver: (docId) async => 'project-1',
      );
      addTearDown(transport.dispose);

      final pushed = await transport.push(<SyncOp>[operation]);
      final pulled = await transport.pull(docId: doc.value, since: 0);

      expect(pushed.accepted, hasLength(1));
      expect(pulled, hasLength(1));
      expect(rest.pushCount, 1);
    });

    test('the connector uses the WebSocket scheme of the API', () async {
      Uri? requested;
      final channel = FakeWebSocketChannel();
      final transport = WebSocketSyncTransport(
        rest: StaticTransport(const <SyncOp>[]),
        connector: (uri, {protocols}) async {
          requested = uri;
          return channel;
        },
        baseUrl: Uri.parse('https://api.limpid.test'),
        projectIdResolver: (docId) async => 'project-1',
      );
      addTearDown(transport.dispose);
      final subscription = transport.connect(doc.value).listen((_) {});
      addTearDown(() async {
        await channel.closeChannel();
        await subscription.cancel();
      });
      await _pump();

      expect(requested, isNotNull);
      expect(requested!.scheme, 'wss');
      expect(requested!.path, '/v1/sync');
    });

    test('the token of the session travels in the handshake', () async {
      Uri? requested;
      final channel = FakeWebSocketChannel();
      final transport = WebSocketSyncTransport(
        rest: StaticTransport(const <SyncOp>[]),
        connector: (uri, {protocols}) async {
          requested = uri;
          return channel;
        },
        baseUrl: Uri.parse('https://api.limpid.test'),
        projectIdResolver: (docId) async => 'project-1',
        tokenProvider: () async => 'jwt-1',
      );
      addTearDown(transport.dispose);
      final subscription = transport.connect(doc.value).listen((_) {});
      addTearDown(() async {
        await channel.closeChannel();
        await subscription.cancel();
      });
      await _pump();

      expect(requested!.queryParameters['token'], 'jwt-1');
    });
  });
}

/// Lets the pending microtasks and timers run.
Future<void> _pump() async {
  await Future<void>.delayed(const Duration(milliseconds: 10));
}
