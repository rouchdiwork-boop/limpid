import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:limpid_app/src/data/api_client.dart';
import 'package:limpid_app/src/domain/errors.dart';

void main() {
  group('ApiClient', () {
    test('déroule l’enveloppe des réponses', () async {
      final ApiClient client = _clientOf((http.Request request) async {
        expect(request.url.path, '/v1/projects');
        return _json(<String, Object?>{
          'data': <String, Object?>{'id': 'project-1'},
        });
      });

      final Object? payload = await client.get('/v1/projects');

      expect(payload, isA<Map<String, Object?>>());
      expect((payload! as Map<String, Object?>)['id'], 'project-1');
    });

    test('envoie le jeton d’authentification quand il y en a un', () async {
      String? authorization;
      final ApiClient client = _clientOf((http.Request request) async {
        authorization = request.headers['authorization'];
        return _json(<String, Object?>{'data': <String, Object?>{}});
      }, token: () async => 'jeton');

      await client.get('/v1/projects');

      expect(authorization, 'Bearer jeton');
    });

    test('n’envoie aucun jeton quand il n’y en a pas', () async {
      String? authorization;
      final ApiClient client = _clientOf((http.Request request) async {
        authorization = request.headers['authorization'];
        return _json(<String, Object?>{'data': <String, Object?>{}});
      });

      await client.get('/v1/projects');

      expect(authorization, isNull);
    });

    test('remonte une erreur typée sur un 400', () async {
      final ApiClient client = _clientOf(
        (http.Request request) async =>
            _error(400, 'validation_failed', 'Le titre est obligatoire.'),
      );

      await expectLater(
        client.get('/v1/projects'),
        throwsA(
          isA<ApiValidationException>()
              .having((ApiValidationException e) => e.statusCode, 'status', 400)
              .having(
                (ApiValidationException e) => e.code,
                'code',
                'validation_failed',
              )
              .having(
                (ApiValidationException e) => e.message,
                'message',
                'Le titre est obligatoire.',
              ),
        ),
      );
    });

    test('remonte une erreur typée sur un 401', () async {
      final ApiClient client = _clientOf(
        (http.Request request) async =>
            _error(401, 'unauthorized', 'Les identifiants sont refusés.'),
      );

      await expectLater(
        client.get('/v1/projects'),
        throwsA(
          isA<ApiUnauthorizedException>().having(
            (ApiUnauthorizedException e) => e.statusCode,
            'status',
            401,
          ),
        ),
      );
    });

    test('remonte une erreur typée sur un 404', () async {
      final ApiClient client = _clientOf(
        (http.Request request) async =>
            _error(404, 'not_found', 'Ce projet n’existe pas.'),
      );

      await expectLater(
        client.get('/v1/projects/inconnu'),
        throwsA(
          isA<ApiNotFoundException>().having(
            (ApiNotFoundException e) => e.code,
            'code',
            'not_found',
          ),
        ),
      );
    });

    test('remonte une erreur typée sur un 500', () async {
      final ApiClient client = _clientOf(
        (http.Request request) async =>
            _error(500, 'internal_error', 'Le serveur a échoué.'),
      );

      await expectLater(
        client.get('/v1/projects'),
        throwsA(
          isA<ApiServerException>()
              .having((ApiServerException e) => e.statusCode, 'status', 500)
              .having(
                (ApiServerException e) => e.message,
                'message',
                'Le serveur a échoué.',
              ),
        ),
      );
    });

    test('remonte une erreur typée quand le serveur est injoignable', () async {
      final ApiClient client = _clientOf((http.Request request) async {
        throw http.ClientException('Connection refused', request.url);
      });

      await expectLater(
        client.get('/v1/projects'),
        throwsA(isA<ApiNetworkException>()),
      );
    });

    test('remonte une erreur typée quand le délai est dépassé', () async {
      final ApiClient client = _clientOf((http.Request request) async {
        await Future<void>.delayed(const Duration(milliseconds: 200));
        return _json(<String, Object?>{'data': <String, Object?>{}});
      }, timeout: const Duration(milliseconds: 30));

      await expectLater(
        client.get('/v1/projects'),
        throwsA(isA<ApiTimeoutException>()),
      );
    });

    test(
      'remonte une erreur typée quand la réponse n’est pas du JSON',
      () async {
        final ApiClient client = _clientOf(
          (http.Request request) async => http.Response('pas du json', 200),
        );

        await expectLater(
          client.get('/v1/projects'),
          throwsA(isA<ApiMalformedResponseException>()),
        );
      },
    );

    test('remonte une erreur typée quand l’enveloppe est absente', () async {
      final ApiClient client = _clientOf(
        (http.Request request) async => http.Response(
          jsonEncode(<String, Object?>{'id': 'project-1'}),
          200,
        ),
      );

      await expectLater(
        client.get('/v1/projects'),
        throwsA(isA<ApiMalformedResponseException>()),
      );
    });
  });
}

/// Builds a client talking to a fake server.
ApiClient _clientOf(
  Future<http.Response> Function(http.Request request) handler, {
  Future<String?> Function()? token,
  Duration timeout = const Duration(seconds: 5),
}) => ApiClient(
  baseUrl: Uri.parse('https://api.test'),
  client: MockClient(handler),
  tokenProvider: token,
  requestTimeout: timeout,
);

/// Builds a JSON answer.
http.Response _json(Map<String, Object?> body) => http.Response(
  jsonEncode(body),
  200,
  headers: <String, String>{'content-type': 'application/json'},
);

/// Builds an error answer.
http.Response _error(int status, String code, String message) => http.Response(
  jsonEncode(<String, Object?>{
    'error': <String, Object?>{'code': code, 'message': message},
  }),
  status,
  headers: <String, String>{'content-type': 'application/json'},
);
