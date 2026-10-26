import 'package:http/http.dart' as http;
import 'package:limpid_ai/limpid_ai.dart';
import 'package:test/test.dart';

import 'helpers/fake_http_client.dart';

void main() {
  AiPrompt buildPrompt() {
    return AiPrompt.systemAndUser(
      system: 'Tu es relecteur.',
      user: 'Relis ce passage.',
    );
  }

  OpenAiCompatibleProvider buildProvider(FakeHttpClient client) {
    return OpenAiCompatibleProvider(
      httpClient: client,
      credentialStore: const _StaticCredentials(),
      baseUrl: 'https://exemple.test/v1',
    );
  }

  group('OpenAiCompatibleProvider', () {
    test('analyse la réponse complète', () async {
      final FakeHttpClient client = FakeHttpClient(
        (http.BaseRequest request) => fakeResponse(
          '{"id":"chatcmpl-1","object":"chat.completion",'
          '"model":"gpt-4o-mini","choices":[{"index":0,'
          '"message":{"role":"assistant","content":"Texte généré."},'
          '"finish_reason":"stop"}],'
          '"usage":{"prompt_tokens":90,"completion_tokens":30,'
          '"total_tokens":120}}',
        ),
      );

      final AiResponse response = await buildProvider(
        client,
      ).complete(buildPrompt());

      expect(response.text, 'Texte généré.');
      expect(response.usage.inputTokens, 90);
      expect(response.usage.outputTokens, 30);
      expect(response.model, 'gpt-4o-mini');
      expect(response.provider, AiProviderKind.openaiCompatible);
    });

    test('cible le bon endpoint et envoie le jeton Bearer', () async {
      final FakeHttpClient client = FakeHttpClient(
        (http.BaseRequest request) => fakeResponse(
          '{"choices":[{"message":{"content":"ok"}}],'
          '"usage":{"prompt_tokens":1,"completion_tokens":1}}',
        ),
      );

      await buildProvider(client).complete(buildPrompt());

      expect(
        client.lastRequest.url.toString(),
        'https://exemple.test/v1/chat/completions',
      );
      expect(client.lastHeaders['authorization'], 'Bearer cle-de-test');
      final Map<String, dynamic> body = client.lastJsonBody;
      final List<dynamic> messages = body['messages'] as List<dynamic>;
      expect((messages.first as Map<String, dynamic>)['role'], 'system');
      expect(messages, hasLength(2));
    });

    test('analyse le flux SSE OpenAI et s\'arrête sur [DONE]', () async {
      const String sse =
          'data: {"id":"1","model":"gpt-4o-mini","choices":'
          '[{"index":0,"delta":{"role":"assistant","content":"Salut"},'
          '"finish_reason":null}]}\n'
          '\n'
          'data: {"id":"1","choices":[{"index":0,"delta":{"content":" !"},'
          '"finish_reason":null}]}\n'
          '\n'
          'data: {"id":"1","choices":[],"usage":{"prompt_tokens":12,'
          '"completion_tokens":3,"total_tokens":15}}\n'
          '\n'
          'data: [DONE]\n'
          '\n'
          'data: {"id":"1","choices":[{"delta":{"content":"ignoré"}}]}\n'
          '\n';

      final FakeHttpClient client = FakeHttpClient(
        (http.BaseRequest request) => fakeChunkedResponse(sse),
      );

      final List<AiChunk> chunks = await buildProvider(
        client,
      ).stream(buildPrompt()).toList();

      expect(
        chunks
            .where((AiChunk chunk) => !chunk.isDone)
            .map((AiChunk chunk) => chunk.text),
        <String>['Salut', ' !'],
      );
      final AiChunk last = chunks.last;
      expect(last.isDone, isTrue);
      expect(last.usage?.inputTokens, 12);
      expect(last.usage?.outputTokens, 3);
      expect(client.lastJsonBody['stream'], isTrue);
    });

    test('traduit une erreur 429 en AiRateLimited', () async {
      final FakeHttpClient client = FakeHttpClient(
        (http.BaseRequest request) => fakeResponse(
          '{"error":{"message":"Trop de requêtes","type":"rate_limit_error"}}',
          statusCode: 429,
        ),
      );

      await expectLater(
        buildProvider(client).complete(buildPrompt()),
        throwsA(
          isA<AiRateLimited>().having(
            (AiRateLimited error) => error.code,
            'code',
            'ai_rate_limited',
          ),
        ),
      );
    });

    test('traduit un filtrage de contenu en AiSafetyRefusal', () async {
      final FakeHttpClient client = FakeHttpClient(
        (http.BaseRequest request) => fakeResponse(
          '{"choices":[{"message":{"content":""},'
          '"finish_reason":"content_filter"}],'
          '"usage":{"prompt_tokens":1,"completion_tokens":0}}',
        ),
      );

      await expectLater(
        buildProvider(client).complete(buildPrompt()),
        throwsA(isA<AiSafetyRefusal>()),
      );
    });
  });
}

class _StaticCredentials implements AiCredentialStore {
  const _StaticCredentials();

  @override
  Future<String?> read(AiProviderKind provider, {String? scope}) async =>
      'cle-de-test';
}
