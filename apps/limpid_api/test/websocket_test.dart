import 'dart:async';
import 'dart:collection';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:limpid_api/limpid_api.dart';
import 'package:limpid_core/limpid_core.dart';
import 'package:test/test.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'helpers/test_server.dart';

void main() {
  late TestServer server;
  late String token;
  late String projectId;

  setUp(() async {
    server = await startTestServer();
    token = server.tokenFor('user-1');
    projectId = await _createProject(server, token);
  });

  tearDown(() async {
    await server.stop();
  });

  test('refuse la connexion sans jeton', () async {
    final _Frames frames = await _connect(server, null);

    final Map<String, dynamic> frame = await frames.next();

    expect(frame['type'], 'error');
    expect((frame['payload']! as Map<String, dynamic>)['code'], 'unauthorized');
  });

  test('accueille le client et relaie les opérations', () async {
    // Le relais n'ouvre une salle que sur un document que le projet possède :
    // le document est donc créé par une poussée HTTP.
    await _pushOperation(server, token, projectId, docId: 'doc-1', lamport: 1);

    final _Frames frames = await _connect(server, token);

    final Map<String, dynamic> hello = await frames.next();
    expect(hello['type'], 'hello');

    frames.send(<String, Object?>{
      'type': 'join',
      'payload': <String, Object?>{'project_id': projectId, 'doc_id': 'doc-1'},
    });

    final Map<String, dynamic> ack = await frames.next();
    expect(ack['type'], 'ack');

    frames.send(<String, Object?>{
      'type': 'op',
      'payload': <String, Object?>{
        'op_id': 'op-1',
        'doc_id': 'doc-1',
        'lamport': 2,
        'author_id': 'user-1',
        'type': 'insertBlock',
        'schema_version': 1,
        'payload': <String, Object?>{
          'block_id': 'block-1',
          'parent_id': null,
          'order_key': '5',
          'type': 'paragraph',
          'content': 'Il pleuvait sur la falaise.',
        },
      },
    });

    final Map<String, dynamic> operationAck = await frames.nextOfType('ack');
    expect((operationAck['payload']! as Map<String, dynamic>)['op_id'], 'op-1');

    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(server.sync.storedOperations(projectId), hasLength(2));
  });

  test('répond pong à un ping', () async {
    final _Frames frames = await _connect(server, token);

    await frames.next();
    frames.send(<String, Object?>{'type': 'ping'});

    final Map<String, dynamic> pong = await frames.next();
    expect(pong['type'], 'pong');
  });

  test('relaisse les opérations poussées par HTTP', () async {
    await _pushOperation(server, token, projectId, docId: 'doc-1', lamport: 1);

    final _Frames frames = await _connect(server, token);
    await frames.next();

    frames.send(<String, Object?>{
      'type': 'join',
      'payload': <String, Object?>{'project_id': projectId, 'doc_id': 'doc-1'},
    });
    await frames.nextOfType('ack');

    await _pushOperation(
      server,
      token,
      projectId,
      docId: 'doc-1',
      lamport: 7,
      opId: 'op-http',
      content: 'Poussée par HTTP.',
    );

    final Map<String, dynamic> relayed = await frames.nextOfType('op');
    final Map<String, dynamic> payload =
        relayed['payload']! as Map<String, dynamic>;
    expect(payload['op_id'], 'op-http');
    expect(payload['lamport'], 7);
  });

  test('refuse un join sur le document d\'un autre projet', () async {
    await _pushOperation(server, token, projectId, docId: 'doc-1', lamport: 1);

    final String attackerToken = server.tokenFor('user-2');
    final String attackerProject = await _createProject(server, attackerToken);

    final _Frames frames = await _connect(server, attackerToken);
    await frames.next();

    frames.send(<String, Object?>{
      'type': 'join',
      'payload': <String, Object?>{
        'project_id': attackerProject,
        'doc_id': 'doc-1',
      },
    });

    final Map<String, dynamic> error = await frames.nextOfType('error');
    final Map<String, dynamic> payload =
        error['payload']! as Map<String, dynamic>;
    expect(payload['code'], 'not_found');
    expect(server.sync.storedOperations(attackerProject), isEmpty);
  });

  test(
    'refuse de relayer une opération sur le document d\'un autre projet',
    () async {
      await _pushOperation(
        server,
        token,
        projectId,
        docId: 'doc-1',
        lamport: 1,
      );

      // La victime écoute la salle de son document.
      final _Frames victim = await _connect(server, token);
      await victim.next();
      victim.send(<String, Object?>{
        'type': 'join',
        'payload': <String, Object?>{
          'project_id': projectId,
          'doc_id': 'doc-1',
        },
      });
      await victim.nextOfType('ack');

      final String attackerToken = server.tokenFor('user-2');
      final String attackerProject = await _createProject(
        server,
        attackerToken,
      );
      final _Frames attacker = await _connect(server, attackerToken);
      await attacker.next();

      attacker.send(<String, Object?>{
        'type': 'op',
        'payload': <String, Object?>{
          'op_id': 'op-intrus',
          'project_id': attackerProject,
          'doc_id': 'doc-1',
          'lamport': 2,
          'author_id': 'user-2',
          'type': 'insertBlock',
          'schema_version': 1,
          'payload': <String, Object?>{
            'block_id': 'block-intrus',
            'parent_id': null,
            'order_key': '9',
            'type': 'paragraph',
            'content': 'Bloc injecté.',
          },
        },
      });

      final Map<String, dynamic> error = await attacker.nextOfType('error');
      final Map<String, dynamic> payload =
          error['payload']! as Map<String, dynamic>;
      expect(payload['code'], 'not_found');

      await Future<void>.delayed(const Duration(milliseconds: 100));

      // L'opération n'est pas stockée dans le projet de l'attaquant...
      expect(server.sync.storedOperations(attackerProject), isEmpty);
      // ...ni diffusée dans la salle de la victime.
      expect(victim.framesOfType('op'), isEmpty);
      expect(server.sync.storedOperations(projectId), hasLength(1));
    },
  );

  test('appose l\'auteur de l\'appelant sur une opération', () async {
    await _pushOperation(server, token, projectId, docId: 'doc-1', lamport: 1);

    final _Frames frames = await _connect(server, token);
    await frames.next();
    frames.send(<String, Object?>{
      'type': 'join',
      'payload': <String, Object?>{'project_id': projectId, 'doc_id': 'doc-1'},
    });
    await frames.nextOfType('ack');

    frames.send(<String, Object?>{
      'type': 'op',
      'payload': <String, Object?>{
        'op_id': 'op-2',
        'doc_id': 'doc-1',
        'lamport': 2,
        'author_id': 'user-9',
        'type': 'insertBlock',
        'schema_version': 1,
        'payload': <String, Object?>{
          'block_id': 'block-2',
          'parent_id': null,
          'order_key': '5',
          'type': 'paragraph',
          'content': 'Un texte.',
        },
      },
    });

    await frames.nextOfType('ack');
    await Future<void>.delayed(const Duration(milliseconds: 100));

    final List<SyncOpRecord> stored = server.sync.storedOperations(projectId);
    expect(stored, hasLength(2));
    expect(stored.last.authorId, 'user-1');
    expect(stored.last.lamport, 2);
  });

  group('présence', () {
    test('annonce la jonction, le curseur et le départ', () async {
      await _pushOperation(
        server,
        token,
        projectId,
        docId: 'doc-1',
        lamport: 1,
      );
      server.projects.addMember(
        projectId: projectId,
        userId: 'user-2',
        role: ProjectRole.coAuthor,
      );
      final String otherToken = server.tokenFor('user-2');

      final _Frames alice = await _connect(server, token);
      await alice.next();
      alice.send(_joinFrame(projectId, 'doc-1'));
      await alice.nextOfType('ack');

      final _Frames bob = await _connect(server, otherToken);
      await bob.next();
      bob.send(_joinFrame(projectId, 'doc-1'));
      await bob.nextOfType('ack');

      // Alice apprend que Bob est dans la salle.
      final Map<String, dynamic> joined = await alice.nextOfType('presence');
      final Map<String, dynamic> joinedPayload =
          joined['payload']! as Map<String, dynamic>;
      expect(joinedPayload['doc_id'], 'doc-1');
      expect(joinedPayload['user_id'], 'user-2');
      expect(joinedPayload['state'], 'joined');

      // Bob apprend qui est déjà là.
      final Map<String, dynamic> roster = await bob.nextOfType('presence');
      final Map<String, dynamic> rosterPayload =
          roster['payload']! as Map<String, dynamic>;
      expect(rosterPayload['user_id'], 'user-1');
      expect(rosterPayload['state'], 'joined');

      // Le curseur de Bob voyage jusqu'à Alice.
      bob.send(<String, Object?>{
        'type': 'cursor',
        'payload': <String, Object?>{
          'project_id': projectId,
          'doc_id': 'doc-1',
          'cursor': <String, Object?>{'block_id': 'block-1', 'offset': 12},
        },
      });
      final Map<String, dynamic> moved = await alice.nextOfType('presence');
      final Map<String, dynamic> movedPayload =
          moved['payload']! as Map<String, dynamic>;
      expect(movedPayload['state'], 'cursor');
      expect(movedPayload['user_id'], 'user-2');
      final Map<String, dynamic> cursor =
          movedPayload['cursor']! as Map<String, dynamic>;
      expect(cursor['block_id'], 'block-1');
      expect(cursor['offset'], 12);

      // Bob part : Alice le voit disparaître.
      await bob.close();
      final Map<String, dynamic> left = await alice.nextOfType('presence');
      final Map<String, dynamic> leftPayload =
          left['payload']! as Map<String, dynamic>;
      expect(leftPayload['state'], 'left');
      expect(leftPayload['user_id'], 'user-2');
    });

    test('purge un pair qui ne bat plus', () async {
      final TestServer relay = await startTestServer(
        configOverrides: <String, String>{
          'LIMPID_RELAY_HEARTBEAT_SECONDS': '1',
          'LIMPID_RELAY_PRESENCE_TIMEOUT_SECONDS': '2',
        },
      );
      addTearDown(relay.stop);
      final String relayToken = relay.tokenFor('user-1');
      final String relayProject = await _createProject(relay, relayToken);
      relay.projects.addMember(
        projectId: relayProject,
        userId: 'user-2',
        role: ProjectRole.coAuthor,
      );
      await _pushOperation(
        relay,
        relayToken,
        relayProject,
        docId: 'doc-1',
        lamport: 1,
      );

      // Alice ne répond jamais au ping du relais : elle ne bat plus.
      final _Frames alice = await _connect(
        relay,
        relayToken,
        answersThePing: false,
      );
      await alice.next();
      alice.send(_joinFrame(relayProject, 'doc-1'));
      await alice.nextOfType('ack');

      final _Frames bob = await _connect(relay, relay.tokenFor('user-2'));
      await bob.next();
      bob.send(_joinFrame(relayProject, 'doc-1'));
      await bob.nextOfType('ack');
      await bob.nextOfType('presence');

      final Map<String, dynamic> left = await bob.nextOfType('presence');
      final Map<String, dynamic> payload =
          left['payload']! as Map<String, dynamic>;
      expect(payload['state'], 'left');
      expect(payload['user_id'], 'user-1');
    });
  });

  test('envoie un ping de garde-fou au client', () async {
    final TestServer relay = await startTestServer(
      configOverrides: <String, String>{
        'LIMPID_RELAY_HEARTBEAT_SECONDS': '1',
        'LIMPID_RELAY_PRESENCE_TIMEOUT_SECONDS': '30',
      },
    );
    addTearDown(relay.stop);

    final _Frames frames = await _connect(relay, relay.tokenFor('user-1'));
    await frames.next();

    final Map<String, dynamic> ping = await frames.nextOfType('ping');
    expect(ping['type'], 'ping');
  });
}

/// The frame that joins the room of [docId].
Map<String, Object?> _joinFrame(String projectId, String docId) {
  return <String, Object?>{
    'type': 'join',
    'payload': <String, Object?>{'project_id': projectId, 'doc_id': docId},
  };
}

/// The frames received on a WebSocket connection.
final class _Frames {
  _Frames(this._channel, {this.answersThePing = true}) {
    _subscription = _channel.stream.listen(
      (dynamic raw) {
        final Map<String, dynamic> frame =
            jsonDecode(raw as String) as Map<String, dynamic>;
        _queue.add(frame);
        // Le client bat : le relais purge les pairs qui se taisent.
        if (answersThePing && frame['type'] == 'ping') {
          _channel.sink.add(jsonEncode(<String, Object?>{'type': 'pong'}));
        }
        if (!_pending.isCompleted) _pending.complete();
      },
      onError: (Object error) {
        _isDone = true;
        if (!_pending.isCompleted) _pending.complete();
      },
      onDone: () {
        _isDone = true;
        if (!_pending.isCompleted) _pending.complete();
      },
    );
  }

  final WebSocketChannel _channel;

  /// Whether the client answers the ping of the relay.
  final bool answersThePing;

  final Queue<Map<String, dynamic>> _queue = Queue<Map<String, dynamic>>();
  Completer<void> _pending = Completer<void>();
  late final StreamSubscription<dynamic> _subscription;
  bool _isDone = false;

  /// Closes the connection and releases the subscription.
  Future<void> close() async {
    await _subscription.cancel();
    await _channel.sink.close();
  }

  /// Sends a frame.
  void send(Map<String, Object?> frame) {
    _channel.sink.add(jsonEncode(frame));
  }

  /// Waits for the next frame.
  Future<Map<String, dynamic>> next() async {
    while (_queue.isEmpty) {
      if (_isDone) {
        throw StateError('La connexion a été fermée.');
      }
      if (_pending.isCompleted) {
        _pending = Completer<void>();
      } else {
        await _pending.future;
      }
    }
    return _queue.removeFirst();
  }

  /// Waits for the next frame of the given type.
  Future<Map<String, dynamic>> nextOfType(String type) async {
    while (true) {
      final Map<String, dynamic> frame = await next();
      if (frame['type'] == type) return frame;
    }
  }

  /// The frames of the given type received so far.
  List<Map<String, dynamic>> framesOfType(String type) {
    return _queue
        .where((Map<String, dynamic> frame) => frame['type'] == type)
        .toList(growable: false);
  }
}

Future<_Frames> _connect(
  TestServer server,
  String? token, {
  bool answersThePing = true,
}) async {
  final Uri uri = Uri.parse(
    'ws://127.0.0.1:${server.server.port}/v1/sync'
    '${token == null ? '' : '?token=$token'}',
  );
  final WebSocketChannel channel = WebSocketChannel.connect(uri);
  final _Frames frames = _Frames(channel, answersThePing: answersThePing);
  addTearDown(frames.close);
  return frames;
}

Future<String> _createProject(TestServer server, String token) async {
  final http.Response response = await server.post(
    '/v1/projects',
    headers: <String, String>{'authorization': 'Bearer $token'},
    body: <String, Object?>{'title': 'Manuscrit'},
  );
  final Map<String, dynamic> body =
      jsonDecode(response.body) as Map<String, dynamic>;
  return (body['data'] as Map<String, dynamic>)['id'] as String;
}

/// Pushes an operation on the route of the project.
///
/// The push binds the document to the project: the relay only opens a room
/// on a document the journal already knows.
Future<void> _pushOperation(
  TestServer server,
  String token,
  String projectId, {
  required String docId,
  required int lamport,
  String? opId,
  String content = 'Il pleuvait sur la falaise.',
}) async {
  final http.Response response = await server.post(
    '/v1/projects/$projectId/ops',
    headers: <String, String>{'authorization': 'Bearer $token'},
    body: <String, Object?>{
      'operations': <dynamic>[
        <String, Object?>{
          'op_id': opId ?? 'op-$lamport',
          'doc_id': docId,
          'lamport': lamport,
          'author_id': 'user-1',
          'type': 'insertBlock',
          'schema_version': 1,
          'payload': <String, Object?>{
            'block_id': 'block-$lamport',
            'parent_id': null,
            'order_key': '5',
            'type': 'paragraph',
            'content': content,
          },
        },
      ],
    },
  );
  expect(response.statusCode, 200);
}
