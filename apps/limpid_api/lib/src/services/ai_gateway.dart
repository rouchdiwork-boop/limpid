/// The actions accepted by the inline rewriting.
const Set<String> aiInlineActions = <String>{
  'expand',
  'shorten',
  'simplify',
  'changeTone',
  'translate',
};

/// A piece of an AI answer, streamed to the client.
sealed class AiEvent {
  /// Creates an event.
  const AiEvent();
}

/// A fragment of the generated text.
final class AiTokenEvent extends AiEvent {
  /// Creates a token event.
  const AiTokenEvent(this.text);

  /// The fragment of text.
  final String text;
}

/// The end of the answer, with its consumption.
final class AiDoneEvent extends AiEvent {
  /// Creates a done event.
  ///
  /// [isTokenCountEstimated] is `true` unless the gateway declares that
  /// the provider reported its own usage.
  const AiDoneEvent({
    required this.text,
    required this.inputTokens,
    required this.outputTokens,
    required this.estimatedCostUsd,
    this.isTokenCountEstimated = true,
  });

  /// The complete text of the answer.
  final String text;

  /// The number of tokens read by the model.
  final int inputTokens;

  /// The number of tokens written by the model.
  final int outputTokens;

  /// The estimated cost of the call, in US dollars.
  final double estimatedCostUsd;

  /// Whether the token counts are an estimate rather than the provider's own
  /// report.
  ///
  /// The default is `true`: a gateway that does not declare its numbers as
  /// the provider's report is estimating, and an estimate that pretends to
  /// be exact ends up in the invoice of an author.
  final bool isTokenCountEstimated;
}

/// A free generation request.
final class AiGenerateRequest {
  /// Creates a request.
  const AiGenerateRequest({
    required this.userId,
    required this.prompt,
    this.system,
    this.taskKey,
    this.maxTokens,
    this.temperature,
  });

  /// The author the call is billed to.
  final String userId;

  /// The instruction sent to the model.
  final String prompt;

  /// The system prompt, when the caller brings its own.
  final String? system;

  /// The key of the task of the registry driving the call.
  final String? taskKey;

  /// The ceiling of the generated tokens.
  final int? maxTokens;

  /// The sampling temperature.
  final double? temperature;
}

/// An inline rewriting request.
final class AiInlineRequest {
  /// Creates a request.
  const AiInlineRequest({
    required this.userId,
    required this.action,
    required this.text,
    this.tone,
    this.instruction,
    this.targetLanguage = 'français',
    this.context,
    this.maxTokens,
  });

  /// The author the call is billed to.
  final String userId;

  /// The rewriting action.
  final String action;

  /// The text to rewrite.
  final String text;

  /// The expected tone, for the tone change action.
  final String? tone;

  /// A free instruction added to the action.
  final String? instruction;

  /// The target language, for the translation action.
  final String targetLanguage;

  /// The narrative context of the passage.
  final String? context;

  /// The ceiling of the generated tokens.
  final int? maxTokens;
}

/// A passage of the manuscript offered to the retrieval augmented search.
final class ManuscriptSource {
  /// Creates a source.
  const ManuscriptSource({required this.id, required this.text});

  /// The identifier of the passage.
  final String id;

  /// The text of the passage.
  final String text;
}

/// A question asked to the manuscript.
final class AiQueryRequest {
  /// Creates a request.
  const AiQueryRequest({
    required this.userId,
    required this.question,
    this.sources = const <ManuscriptSource>[],
    this.topK = 6,
    this.scope,
  });

  /// The author the call is billed to.
  final String userId;

  /// The question.
  final String question;

  /// The passages of the manuscript the search runs on.
  final List<ManuscriptSource> sources;

  /// The number of passages kept.
  final int topK;

  /// The scope of the search, for example a project identifier.
  final String? scope;
}

/// The AI capability of the API.
///
/// The routes depend on this interface only, which lets the test suite run
/// without any provider.
abstract interface class AiGateway {
  /// Vérifie que le compte [userId] a autorisé l'envoi de son texte.
  ///
  /// La vérification est **avant** l'appel : elle lève une exception, et
  /// l'appel n'a pas lieu. Le flux de la réponse n'est jamais ouvert.
  ///
  /// La garde fait partie du **contrat** de la passerelle, et non d'une
  /// interface séparée : une passerelle qui interroge un tiers ne peut
  /// pas l'oublier, et une passerelle qui n'a personne en face refuse
  /// l'appel de toute façon.
  Future<void> ensureConsent({required String userId});

  /// Streams the answer of a free generation.
  Stream<AiEvent> generate(AiGenerateRequest request);

  /// Streams the answer of an inline rewriting.
  Stream<AiEvent> inline(AiInlineRequest request);

  /// Streams the answer of a question asked to the manuscript.
  Stream<AiEvent> query(AiQueryRequest request);
}
