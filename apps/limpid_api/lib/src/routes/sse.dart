import 'dart:async';
import 'dart:convert';

import 'package:shelf/shelf.dart';

import '../errors/app_exception.dart';
import '../logging/logger.dart';
import '../services/ai_gateway.dart';

/// The headers of a server sent events response.
const Map<String, String> sseHeaders = <String, String>{
  'content-type': 'text/event-stream; charset=utf-8',
  'cache-control': 'no-cache, no-transform',
  'connection': 'keep-alive',
  'x-accel-buffering': 'no',
};

/// Builds the server sent events response of an AI answer.
///
/// The stream carries one `token` event per fragment, then a `done` event
/// holding the complete text and the consumption of the call. A failure
/// happening after the first byte is reported as an `error` event, because
/// the status code is already sent.
Response sseResponse(Stream<AiEvent> events, {required Logger logger}) {
  final StreamController<List<int>> controller = StreamController<List<int>>();
  late final StreamSubscription<AiEvent> subscription;
  subscription = events.listen(
    (AiEvent event) => controller.add(utf8.encode(_format(event))),
    onError: (Object error) {
      logger.error('ai.stream_failed', <String, Object?>{
        'error': error.runtimeType.toString(),
      });
      controller.add(
        utf8.encode(
          _formatError(
            error is AppException
                ? error
                : const InternalException(
                    message: 'Le service IA a interrompu la réponse.',
                  ),
          ),
        ),
      );
      controller.close();
    },
    onDone: () => controller.close(),
    cancelOnError: false,
  );
  controller.onCancel = subscription.cancel;

  return Response.ok(controller.stream, headers: sseHeaders);
}

String _format(AiEvent event) {
  return switch (event) {
    AiTokenEvent(:final text) =>
      'event: token\ndata: ${jsonEncode(<String, Object?>{'text': text})}\n\n',
    AiDoneEvent(
      :final text,
      :final inputTokens,
      :final outputTokens,
      :final estimatedCostUsd,
    ) =>
      'event: done\ndata: '
          '${jsonEncode(<String, Object?>{'text': text, 'input_tokens': inputTokens, 'output_tokens': outputTokens, 'estimated_cost_usd': estimatedCostUsd})}\n\n',
  };
}

String _formatError(AppException error) {
  return 'event: error\ndata: '
      '${jsonEncode(<String, Object?>{'code': error.code, 'message': error.message, 'details': error.details})}\n\n';
}
