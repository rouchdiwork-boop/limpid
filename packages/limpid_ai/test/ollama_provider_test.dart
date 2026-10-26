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

  OllamaProvider buildProvider(FakeHttpClient client) {
    return OllamaProvider(
      httpClient: client,
      credentialStore: const _EmptyCredentials(),
      baseUrl: 'http://localhost:11434',
    );
  }

  group('OllamaProvider', () {
    test('analyse la réponse complète locale', () async {
      final FakeHttpClient client = FakeHttpClient(
        (http.BaseRequest request) => fakeResponse(
          '{"model":"llama3.1","created_at":"2026-01-01T00:00:00Z",'
          '"message":{"role":"assistant","content":"Texte local."},"done":true,'
          '"prompt_eval_count":18,"eval_count":7}',
        ),
      );

      final AiResponse response = await buildProvider(
        client,
      ).complete(buildPrompt());

      expect(response.text, 'Texte local.');
      expect(response.usage.inputTokens, 18);
      expect(response.usage.outputTokens, 7);
      expect(response.usage.estimatedCostUsd, 0);
      expect(response.provider, AiProviderKind.ollama);
      expect(client.lastRequest.url.toString(), contains('/api/chat'));
    });

    test('analyse le flux NDJSON local', () async {
      const String ndjson =
          '{"model":"llama3.1","message":{"role":'
          '"assistant","content":"Bonjour"},"done":false}\n'
          '{"model":"llama3.1","message":{"role":"assistant",'
          '"content":" le monde"},"done":true,"prompt_eval_count":8,'
          '"eval_count":4}\n';

      final FakeHttpClient client = FakeHttpClient(
        (http.BaseRequest request) =>
            fakeChunkedResponse(ndjson, chunkSize: 13),
      );

      final List<AiChunk> chunks = await buildProvider(
        client,
      ).stream(buildPrompt()).toList();

      expect(
        chunks
            .where((AiChunk chunk) => !chunk.isDone)
            .map((AiChunk chunk) => chunk.text),
        <String>['Bonjour', ' le monde'],
      );
      final AiChunk last = chunks.last;
      expect(last.isDone, isTrue);
      expect(last.usage?.inputTokens, 8);
      expect(last.usage?.outputTokens, 4);
    });

    test('n\'exige aucune clé d\'API', () async {
      final FakeHttpClient client = FakeHttpClient(
        (http.BaseRequest request) =>
            fakeResponse('{"message":{"content":"ok"},"done":true}'),
      );

      await buildProvider(client).complete(buildPrompt());

      expect(client.lastHeaders.containsKey('authorization'), isFalse);
    });
  });
}

class _EmptyCredentials implements AiCredentialStore {
  const _EmptyCredentials();

  @override
  Future<String?> read(AiProviderKind provider, {String? scope}) async => null;
}
