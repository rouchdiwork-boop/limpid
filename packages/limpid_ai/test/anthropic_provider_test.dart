import 'package:http/http.dart' as http;
import 'package:limpid_ai/limpid_ai.dart';
import 'package:test/test.dart';

import 'helpers/fake_http_client.dart';

void main() {
  const AiCredentialStore credentials = _StaticCredentials();

  AiPrompt buildPrompt() {
    return AiPrompt.systemAndUser(
      system: 'Tu es relecteur.',
      user: 'Relis ce passage.',
    );
  }

  group('AnthropicProvider', () {
    test('analyse la réponse complète et compte les tokens', () async {
      final FakeHttpClient client = FakeHttpClient(
        (http.BaseRequest request) => fakeResponse(
          '{"id":"msg_1","type":"message","role":"assistant",'
          '"model":"claude-sonnet-5-5","content":[{"type":"text",'
          '"text":"Texte généré."}],"stop_reason":"end_turn",'
          '"usage":{"input_tokens":120,"output_tokens":45}}',
        ),
      );
      final AnthropicProvider provider = AnthropicProvider(
        httpClient: client,
        credentialStore: credentials,
      );

      final AiResponse response = await provider.complete(buildPrompt());

      expect(response.text, 'Texte généré.');
      expect(response.usage.inputTokens, 120);
      expect(response.usage.outputTokens, 45);
      expect(response.model, 'claude-sonnet-5-5');
      expect(response.provider, AiProviderKind.anthropic);
      expect(response.usage.estimatedCostUsd, greaterThan(0));
    });

    test('envoie la clé, la version d\'API et le corps attendu', () async {
      final FakeHttpClient client = FakeHttpClient(
        (http.BaseRequest request) => fakeResponse(
          '{"content":[{"type":"text","text":"ok"}],'
          '"usage":{"input_tokens":1,"output_tokens":1}}',
        ),
      );
      final AnthropicProvider provider = AnthropicProvider(
        httpClient: client,
        credentialStore: credentials,
      );

      await provider.complete(buildPrompt());

      expect(client.lastHeaders['x-api-key'], 'cle-de-test');
      expect(client.lastHeaders['anthropic-version'], '2023-06-01');
      final Map<String, dynamic> body = client.lastJsonBody;
      expect(body['system'], 'Tu es relecteur.');
      expect(body['stream'], isFalse);
      expect(body['max_tokens'], isA<int>());
      final List<dynamic> messages = body['messages'] as List<dynamic>;
      expect(messages, hasLength(1));
      expect(
        (messages.first as Map<String, dynamic>)['content'],
        'Relis ce passage.',
      );
    });

    test('analyse le flux SSE Anthropic fragment par fragment', () async {
      const String sse =
          'event: message_start\n'
          'data: {"type":"message_start","message":{"usage":'
          '{"input_tokens":25,"output_tokens":1}}}\n'
          '\n'
          'event: content_block_delta\n'
          'data: {"type":"content_block_delta","index":0,"delta":'
          '{"type":"text_delta","text":"Bonjour"}}\n'
          '\n'
          'event: content_block_delta\n'
          'data: {"type":"content_block_delta","index":0,"delta":'
          '{"type":"text_delta","text":" le monde"}}\n'
          '\n'
          'event: message_delta\n'
          'data: {"type":"message_delta","delta":{"stop_reason":"end_turn"},'
          '"usage":{"output_tokens":9}}\n'
          '\n'
          'event: message_stop\n'
          'data: {"type":"message_stop"}\n'
          '\n';

      final FakeHttpClient client = FakeHttpClient(
        (http.BaseRequest request) => fakeChunkedResponse(sse),
      );
      final AnthropicProvider provider = AnthropicProvider(
        httpClient: client,
        credentialStore: credentials,
      );

      final List<AiChunk> chunks = await provider
          .stream(buildPrompt())
          .toList();

      expect(
        chunks
            .where((AiChunk chunk) => !chunk.isDone)
            .map((AiChunk chunk) => chunk.text),
        <String>['Bonjour', ' le monde'],
      );
      final AiChunk last = chunks.last;
      expect(last.isDone, isTrue);
      expect(last.usage?.inputTokens, 25);
      expect(last.usage?.outputTokens, 9);
      expect(last.usage?.estimatedCostUsd, greaterThan(0));
      expect(client.lastJsonBody['stream'], isTrue);
    });

    test('traduit une erreur 429 en AiRateLimited', () async {
      final FakeHttpClient client = FakeHttpClient(
        (http.BaseRequest request) => fakeResponse(
          '{"type":"error","error":{"type":"rate_limit_error",'
          '"message":"Trop de requêtes"}}',
          statusCode: 429,
          headers: <String, String>{'retry-after': '12'},
        ),
      );
      final AnthropicProvider provider = AnthropicProvider(
        httpClient: client,
        credentialStore: credentials,
      );

      await expectLater(
        provider.complete(buildPrompt()),
        throwsA(
          isA<AiRateLimited>()
              .having(
                (AiRateLimited error) => error.code,
                'code',
                'ai_rate_limited',
              )
              .having(
                (AiRateLimited error) => error.statusCode,
                'statusCode',
                429,
              )
              .having(
                (AiRateLimited error) => error.retryAfter,
                'retryAfter',
                const Duration(seconds: 12),
              ),
        ),
      );
    });

    test(
      'traduit une erreur 401 en AiProviderError d\'authentification',
      () async {
        final FakeHttpClient client = FakeHttpClient(
          (http.BaseRequest request) => fakeResponse(
            '{"type":"error","error":{"type":"authentication_error",'
            '"message":"Clé invalide"}}',
            statusCode: 401,
          ),
        );
        final AnthropicProvider provider = AnthropicProvider(
          httpClient: client,
          credentialStore: credentials,
        );

        await expectLater(
          provider.complete(buildPrompt()),
          throwsA(
            isA<AiProviderError>().having(
              (AiProviderError error) => error.code,
              'code',
              'ai_auth_error',
            ),
          ),
        );
      },
    );

    test('signale une réponse illisible', () async {
      final FakeHttpClient client = FakeHttpClient(
        (http.BaseRequest request) => fakeResponse('pas du json'),
      );
      final AnthropicProvider provider = AnthropicProvider(
        httpClient: client,
        credentialStore: credentials,
      );

      await expectLater(
        provider.complete(buildPrompt()),
        throwsA(isA<AiInvalidResponse>()),
      );
    });

    test('refuse un appel sans clé configurée', () async {
      final FakeHttpClient client = FakeHttpClient(
        (http.BaseRequest request) => fakeResponse('{}'),
      );
      final AnthropicProvider provider = AnthropicProvider(
        httpClient: client,
        credentialStore: const _StaticCredentials(),
        scope: 'absent',
      );

      await expectLater(
        provider.complete(buildPrompt()),
        throwsA(
          isA<AiProviderError>().having(
            (AiProviderError error) => error.code,
            'code',
            'ai_missing_credentials',
          ),
        ),
      );
    });
  });
}

class _StaticCredentials implements AiCredentialStore {
  const _StaticCredentials();

  @override
  Future<String?> read(AiProviderKind provider, {String? scope}) async {
    if (scope == 'absent') {
      return null;
    }
    return 'cle-de-test';
  }
}
