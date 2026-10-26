import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:limpid_ai/limpid_ai.dart';
import 'package:limpid_app/src/data/api_client.dart';
import 'package:limpid_app/src/domain/errors.dart';
import 'package:limpid_app/src/domain/repositories.dart';

/// The assistant of the application, served by the API.
///
/// The API answers with server sent events: a `token` event per fragment,
/// then a `done` event holding the complete text. The repository yields the
/// fragments as they arrive — the interface writes them as they come, it
/// never waits for the whole answer.
final class ApiAiRepository implements AiRepository {
  /// Creates a repository on top of [client].
  ApiAiRepository({
    required this.client,
    this.inlineAction = defaultInlineAction,
  });

  /// The action sent to the inline route when the caller does not choose one.
  ///
  /// The API only accepts the five flavours of its inline route — `expand`,
  /// `shorten`, `simplify`, `changeTone` and `translate` — and refuses the
  /// others with a `400`. The generic rewrite of the contract is therefore
  /// sent as [defaultInlineAction], the flavour the API itself uses when it
  /// does not recognise an action, and the instruction of the caller is
  /// appended to it by the server.
  static const String defaultInlineAction = 'expand';

  /// The client of the API.
  final ApiClient client;

  /// The flavour of the inline route used by [rewrite].
  final String inlineAction;

  @override
  Stream<String> answer({required String projectId, required String question}) {
    return _fragments('/v1/ai/query', <String, Object?>{
      'question': question,
      'project_id': projectId,
    });
  }

  @override
  Stream<String> rewrite({
    required String sceneId,
    required String selection,
    required String instruction,
  }) {
    return _fragments('/v1/ai/inline', <String, Object?>{
      'action': inlineAction,
      'text': selection,
      'instruction': instruction,
      // The inline route ignores the unknown fields: the scene is sent
      // anyway, so the server can use it as soon as it knows the route.
      'scene_id': sceneId,
    });
  }

  /// Reads the fragments of an answer of the API.
  Stream<String> _fragments(String path, Map<String, Object?> body) async* {
    final http.StreamedResponse response = await client.postStream(
      path,
      body: body,
    );
    final Stream<String> lines = response.stream
        .transform(const Utf8Decoder(allowMalformed: true))
        .transform(const LineSplitter());
    var yielded = false;
    await for (final SseEvent event in SseDecoder.decode(lines)) {
      switch (event.event) {
        case 'token':
          final String text = _textOf(event.data);
          if (text.isEmpty) break;
          yielded = true;
          yield text;
        case 'done':
          // The complete text is already streamed by the token events. When
          // the server sent none, the answer is delivered once here.
          if (!yielded) {
            final String text = _textOf(event.data);
            if (text.isNotEmpty) yield text;
          }
        case 'error':
          throw _errorOf(event.data);
        default:
          break;
      }
    }
  }

  /// Reads the text carried by an event.
  static String _textOf(String data) {
    final Object? decoded = _decode(data);
    if (decoded is! Map<String, Object?>) return '';
    final Object? text = decoded['text'];
    return text is String ? text : '';
  }

  /// Reads the error carried by an event.
  static ApiException _errorOf(String data) {
    final Object? decoded = _decode(data);
    if (decoded is! Map<String, Object?>) {
      return const ApiServerException(
        'The assistant interrupted the answer.',
        code: 'ai_stream_error',
      );
    }
    final Object? code = decoded['code'];
    final Object? message = decoded['message'];
    return ApiServerException(
      message is String ? message : 'The assistant interrupted the answer.',
      code: code is String ? code : 'ai_stream_error',
    );
  }

  /// Decodes the payload of an event.
  static Object? _decode(String data) {
    try {
      return jsonDecode(data);
    } on FormatException {
      return null;
    }
  }
}
