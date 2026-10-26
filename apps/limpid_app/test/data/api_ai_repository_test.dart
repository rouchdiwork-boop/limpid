import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:limpid_app/src/data/api_ai_repository.dart';
import 'package:limpid_app/src/data/api_client.dart';
import 'package:limpid_app/src/domain/errors.dart';

void main() {
  group('ApiAiRepository', () {
    test('rend les fragments de la réponse à la question', () async {
      final ApiAiRepository repository = _repositoryOf((
        http.Request request,
      ) async {
        expect(request.url.path, '/v1/ai/query');
        return _events(<String>[
          'event: token\ndata: {"text": "Il "}\n\n',
          'event: token\ndata: {"text": "pleuvait."}\n\n',
          'event: done\ndata: {"text": "Il pleuvait."}\n\n',
        ]);
      });

      final List<String> fragments = await repository
          .answer(projectId: 'project-1', question: 'Que se passe-t-il ?')
          .toList();

      expect(fragments, <String>['Il ', 'pleuvait.']);
    });

    test('envoie la question et le projet', () async {
      Map<String, Object?>? body;
      final ApiAiRepository repository = _repositoryOf((
        http.Request request,
      ) async {
        final Object? decoded = jsonDecode(request.body);
        body = decoded is Map<String, Object?> ? decoded : null;
        return _events(<String>['event: done\ndata: {"text": ""}\n\n']);
      });

      await repository
          .answer(projectId: 'project-1', question: 'Que se passe-t-il ?')
          .toList();

      expect(body?['question'], 'Que se passe-t-il ?');
      expect(body?['project_id'], 'project-1');
    });

    test('rend les fragments de la réécriture', () async {
      final ApiAiRepository repository = _repositoryOf((
        http.Request request,
      ) async {
        expect(request.url.path, '/v1/ai/inline');
        return _events(<String>[
          'event: token\ndata: {"text": "Plus "}\n\n',
          'event: token\ndata: {"text": "tendu."}\n\n',
        ]);
      });

      final List<String> fragments = await repository
          .rewrite(
            sceneId: 'scene-1',
            selection: 'Il pleuvait.',
            instruction: 'Rends la scène plus tendue.',
          )
          .toList();

      expect(fragments, <String>['Plus ', 'tendu.']);
    });

    test('envoie la sélection et la consigne de réécriture', () async {
      Map<String, Object?>? body;
      final ApiAiRepository repository = _repositoryOf((
        http.Request request,
      ) async {
        final Object? decoded = jsonDecode(request.body);
        body = decoded is Map<String, Object?> ? decoded : null;
        return _events(<String>['event: done\ndata: {"text": ""}\n\n']);
      });

      await repository
          .rewrite(
            sceneId: 'scene-1',
            selection: 'Il pleuvait.',
            instruction: 'Rends la scène plus tendue.',
          )
          .toList();

      expect(body?['text'], 'Il pleuvait.');
      expect(body?['instruction'], 'Rends la scène plus tendue.');
      expect(body?['action'], isNotEmpty);
    });

    test('remonte une erreur typée quand le flux signale une erreur', () async {
      final ApiAiRepository repository = _repositoryOf((
        http.Request request,
      ) async {
        return _events(<String>[
          'event: error\ndata: {"code": "provider_failed", "message": '
              '"Le fournisseur a échoué."}\n\n',
        ]);
      });

      await expectLater(
        repository.answer(projectId: 'p', question: 'q').toList(),
        throwsA(
          isA<ApiServerException>()
              .having(
                (ApiServerException e) => e.code,
                'code',
                'provider_failed',
              )
              .having(
                (ApiServerException e) => e.message,
                'message',
                'Le fournisseur a échoué.',
              ),
        ),
      );
    });

    test(
      'remonte une erreur typée quand le serveur refuse la requête',
      () async {
        final ApiAiRepository repository = _repositoryOf((
          http.Request request,
        ) async {
          return http.Response(
            jsonEncode(<String, Object?>{
              'error': <String, Object?>{
                'code': 'validation_failed',
                'message': 'La question est obligatoire.',
              },
            }),
            400,
            headers: <String, String>{'content-type': 'application/json'},
          );
        });

        await expectLater(
          repository.answer(projectId: 'p', question: 'q').toList(),
          throwsA(isA<ApiValidationException>()),
        );
      },
    );
  });
}

/// Builds a repository talking to a fake server.
ApiAiRepository _repositoryOf(
  Future<http.Response> Function(http.Request request) handler,
) => ApiAiRepository(
  client: ApiClient(
    baseUrl: Uri.parse('https://api.test'),
    client: MockClient(handler),
  ),
);

/// Builds an answer carrying server sent events.
http.Response _events(List<String> events) => http.Response.bytes(
  utf8.encode(events.join()),
  200,
  headers: <String, String>{'content-type': 'text/event-stream'},
);
