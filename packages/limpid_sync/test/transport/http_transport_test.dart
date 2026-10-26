import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:limpid_core/limpid_core.dart' hide SyncTransport;
import 'package:limpid_sync/limpid_sync.dart';
import 'package:test/test.dart';

import '../support/fake_http_client.dart';

void main() {
  group('HttpSyncTransport', () {
    const doc = DocumentId('doc-http');
    final operation = InsertBlockOp(
      doc: doc,
      lamport: 3,
      author: const AuthorId('author-a'),
      blockId: const BlockId('block-1'),
      parent: null,
      order: OrderKey.initial,
      type: BlockType.paragraph,
      content: const TextContent('Il pleuvait.'),
    );

    test('push posts the operations and decodes the answer', () async {
      final client = FakeHttpClient((request) async {
        if (request.method == 'POST') {
          return jsonStreamedResponse(
            jsonEncode(<String, Object?>{
              'accepted': <Object?>[OpCodec.encode(operation)],
              'duplicated': <Object?>[],
              'rejected': <Object?>[],
              'lamport_ack': 4,
            }),
          );
        }
        return jsonStreamedResponse(
          jsonEncode(<String, Object?>{
            'operations': <Object?>[OpCodec.encode(operation)],
          }),
        );
      });
      final transport = HttpSyncTransport(
        baseUrl: Uri.parse('https://api.limpid.test'),
        client: client,
        tokenProvider: () async => 'a-token',
      );
      addTearDown(transport.dispose);

      final result = await transport.push(<SyncOp>[operation]);

      expect(result.accepted, hasLength(1));
      expect(result.accepted.single, operation);
      expect(result.lamportAck, 4);
      expect(client.requests, hasLength(1));
      final request = client.requests.single as http.Request;
      expect(request.method, 'POST');
      expect(request.url.path, '/v1/projects/doc-http/ops');
      expect(request.headers['authorization'], 'Bearer a-token');
      final body = client.jsonBodies.single;
      final operations = body['operations']! as List<Object?>;
      expect(operations, hasLength(1));
    });

    test('pull reads the operations and forwards the cursor', () async {
      final client = FakeHttpClient(
        (request) async => jsonStreamedResponse(
          jsonEncode(<String, Object?>{
            'operations': <Object?>[OpCodec.encode(operation)],
          }),
        ),
      );
      final transport = HttpSyncTransport(
        baseUrl: Uri.parse('https://api.limpid.test'),
        client: client,
      );
      addTearDown(transport.dispose);

      final operations = await transport.pull(
        docId: doc.value,
        since: 12,
        limit: 50,
      );

      expect(operations, hasLength(1));
      expect(operations.single, operation);
      final request = client.requests.single as http.Request;
      expect(request.url.queryParameters['since'], '12');
      expect(request.url.queryParameters['limit'], '50');
    });

    test('a rejected operation is reported as rejected', () async {
      final client = FakeHttpClient(
        (request) async => jsonStreamedResponse(
          jsonEncode(<String, Object?>{
            'accepted': <Object?>[],
            'duplicated': <Object?>[],
            'rejected': <Object?>[
              <String, Object?>{
                'op_id': operation.operationKey,
                'code': 'schema_version_unsupported',
                'message': 'Version de protocole refusée.',
              },
            ],
            'lamport_ack': 0,
          }),
        ),
      );
      final transport = HttpSyncTransport(
        baseUrl: Uri.parse('https://api.limpid.test'),
        client: client,
      );
      addTearDown(transport.dispose);

      final result = await transport.push(<SyncOp>[operation]);

      expect(result.rejected, hasLength(1));
      expect(result.rejected.single.code, 'schema_version_unsupported');
      expect(result.rejected.single.operationKey, operation.operationKey);
    });

    test('a rejected operation without an identifier is not dropped', () async {
      final client = FakeHttpClient(
        (request) async => jsonStreamedResponse(
          jsonEncode(<String, Object?>{
            'accepted': <Object?>[],
            'duplicated': <Object?>[],
            'rejected': <Object?>[
              <String, Object?>{
                'code': 'validation_failed',
                'message': 'Chaque opération doit être un objet JSON.',
                'field': 'operations',
              },
            ],
            'lamport_ack': 0,
          }),
        ),
      );
      final transport = HttpSyncTransport(
        baseUrl: Uri.parse('https://api.limpid.test'),
        client: client,
      );
      addTearDown(transport.dispose);

      final result = await transport.push(<SyncOp>[operation]);

      expect(result.rejected, hasLength(1));
      expect(result.rejected.single.code, 'validation_failed');
      expect(result.rejected.single.operationKey, isNotEmpty);
    });

    test('the envelope of the API is unwrapped by the push', () async {
      final client = FakeHttpClient(
        (request) async => jsonStreamedResponse(
          jsonEncode(<String, Object?>{
            'data': <String, Object?>{
              'accepted': <Object?>[OpCodec.encode(operation)],
              'duplicated': <Object?>[],
              'rejected': <Object?>[],
              'lamport_ack': 7,
            },
          }),
        ),
      );
      final transport = HttpSyncTransport(
        baseUrl: Uri.parse('https://api.limpid.test'),
        client: client,
      );
      addTearDown(transport.dispose);

      final result = await transport.push(<SyncOp>[operation]);

      expect(result.accepted, hasLength(1));
      expect(result.accepted.single, operation);
      expect(result.lamportAck, 7);
    });

    test('the envelope of the API is unwrapped by the pull', () async {
      final client = FakeHttpClient(
        (request) async => jsonStreamedResponse(
          jsonEncode(<String, Object?>{
            'data': <Object?>[OpCodec.encode(operation)],
          }),
        ),
      );
      final transport = HttpSyncTransport(
        baseUrl: Uri.parse('https://api.limpid.test'),
        client: client,
      );
      addTearDown(transport.dispose);

      final operations = await transport.pull(docId: 'doc-http', since: 0);

      expect(operations, hasLength(1));
      expect(operations.single, operation);
    });

    test('a 401 raises an authentication error', () async {
      final client = FakeHttpClient(
        (request) async => jsonStreamedResponse(
          jsonEncode(<String, Object?>{
            'error': <String, Object?>{
              'code': 'unauthorized',
              'message': 'Jeton absent, invalide ou expiré.',
            },
          }),
          statusCode: 401,
        ),
      );
      final transport = HttpSyncTransport(
        baseUrl: Uri.parse('https://api.limpid.test'),
        client: client,
      );
      addTearDown(transport.dispose);

      expect(
        () => transport.push(<SyncOp>[operation]),
        throwsA(isA<SyncAuthException>()),
      );
    });

    test('a server error raises a transport error', () async {
      final client = FakeHttpClient(
        (request) async => jsonStreamedResponse(
          jsonEncode(<String, Object?>{
            'error': <String, Object?>{
              'code': 'validation_failed',
              'message': 'Échec de validation.',
            },
          }),
          statusCode: 422,
        ),
      );
      final transport = HttpSyncTransport(
        baseUrl: Uri.parse('https://api.limpid.test'),
        client: client,
      );
      addTearDown(transport.dispose);

      expect(
        () => transport.push(<SyncOp>[operation]),
        throwsA(
          isA<SyncTransportException>().having(
            (error) => error.statusCode,
            'statusCode',
            422,
          ),
        ),
      );
    });

    test('an unreachable API raises a network failure', () async {
      final transport = HttpSyncTransport(
        baseUrl: Uri.parse('https://api.limpid.test'),
        client: UnreachableHttpClient(),
      );
      addTearDown(transport.dispose);

      expect(
        () => transport.pull(docId: doc.value, since: 0),
        throwsA(
          isA<SyncTransportException>().having(
            (error) => error.isNetworkFailure,
            'isNetworkFailure',
            isTrue,
          ),
        ),
      );
    });

    test('an empty push does not call the API', () async {
      final client = FakeHttpClient(
        (request) async => jsonStreamedResponse('{}'),
      );
      final transport = HttpSyncTransport(
        baseUrl: Uri.parse('https://api.limpid.test'),
        client: client,
      );
      addTearDown(transport.dispose);

      final result = await transport.push(const <SyncOp>[]);

      expect(result.accepted, isEmpty);
      expect(client.callCount, 0);
    });
  });

  group('HttpConnectivityProbe', () {
    test('the API answers: the device is online', () async {
      final client = FakeHttpClient(
        (request) async => jsonStreamedResponse('{}'),
      );
      final probe = HttpConnectivityProbe(
        baseUrl: Uri.parse('https://api.limpid.test'),
        client: client,
      );

      expect(await probe.isOnline(), isTrue);
    });

    test('the API is unreachable: the device is offline', () async {
      final probe = HttpConnectivityProbe(
        baseUrl: Uri.parse('https://api.limpid.test'),
        client: UnreachableHttpClient(),
      );

      expect(await probe.isOnline(), isFalse);
    });
  });
}
