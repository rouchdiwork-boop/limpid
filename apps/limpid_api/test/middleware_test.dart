import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:limpid_api/limpid_api.dart';
import 'package:test/test.dart';

import 'helpers/test_server.dart';

void main() {
  group('CORS', () {
    late TestServer server;

    setUp(() async {
      server = await startTestServer();
    });

    tearDown(() async {
      await server.stop();
    });

    test('autorise une origine de la liste blanche', () async {
      final http.Response response = await server.get(
        '/health',
        headers: <String, String>{'origin': 'https://app.test'},
      );

      expect(response.statusCode, 200);
      expect(
        response.headers['access-control-allow-origin'],
        'https://app.test',
      );
    });

    test('refuse une origine inconnue', () async {
      final http.Response response = await server.get(
        '/health',
        headers: <String, String>{'origin': 'https://attaquant.test'},
      );

      expect(response.statusCode, 200);
      expect(response.headers['access-control-allow-origin'], isNull);
    });

    test('répond à la requête de pré-vérification', () async {
      final http.Request request = http.Request(
        'OPTIONS',
        Uri.parse('${server.baseUrl}/v1/projects'),
      );
      request.headers['origin'] = 'https://app.test';
      request.headers['access-control-request-method'] = 'POST';

      final http.StreamedResponse streamed = await request.send();
      final http.Response response = await http.Response.fromStream(streamed);

      expect(response.statusCode, 204);
      expect(
        response.headers['access-control-allow-methods'],
        contains('POST'),
      );
    });
  });

  group('journal structuré', () {
    test('ne laisse passer ni secret ni corps de requête', () {
      final List<String> lines = <String>[];
      final Logger captured = Logger(level: LogLevel.debug, sink: lines.add);

      captured.info('request.completed', <String, Object?>{
        'request_id': 'req-1',
        'user_id': 'user-1',
        'authorization': 'Bearer secret',
        'body': 'Il pleuvait sur la falaise.',
        'duration_ms': 12,
      });

      expect(lines, hasLength(1));
      final Map<String, dynamic> record =
          jsonDecode(lines.single) as Map<String, dynamic>;
      expect(record['level'], 'info');
      expect(record['request_id'], 'req-1');
      expect(record['user_id'], 'user-1');
      expect(record['duration_ms'], 12);
      expect(record.containsKey('authorization'), isFalse);
      expect(record.containsKey('body'), isFalse);
      expect(lines.single, isNot(contains('falaise')));
    });

    test('respecte le niveau minimal', () {
      final List<String> lines = <String>[];
      final Logger logger = Logger(level: LogLevel.warning, sink: lines.add);

      logger.debug('discret');
      logger.info('information');
      logger.warning('avertissement');
      logger.error('erreur');

      expect(lines, hasLength(2));
      expect(lines.first, contains('avertissement'));
    });
  });

  group('limitation de débit', () {
    test('autorise puis refuse selon la capacité', () {
      final TokenBucketRateLimiter limiter = TokenBucketRateLimiter(
        capacity: 2,
        refillPerSecond: 0.001,
      );

      expect(limiter.allow('ip-1'), isTrue);
      expect(limiter.allow('ip-1'), isTrue);
      expect(limiter.allow('ip-1'), isFalse);
      expect(limiter.allow('ip-2'), isTrue);
    });
  });
}
