import 'package:limpid_ai/src/model/ai_message.dart';

/// Requête adressée à un modèle de langage.
///
/// La liste [messages] est immuable. Les messages système éventuels sont
/// extraits par les fournisseurs selon leur format (champ `system` chez
/// Anthropic, premier message `role: system` chez OpenAI).
class AiPrompt {
  /// Crée un prompt à partir d'une liste de messages.
  AiPrompt({required List<AiMessage> messages})
    : messages = List<AiMessage>.unmodifiable(messages);

  /// Prompt composé d'une consigne système et d'un message utilisateur.
  factory AiPrompt.systemAndUser({
    required String system,
    required String user,
  }) {
    return AiPrompt(
      messages: <AiMessage>[AiMessage.system(system), AiMessage.user(user)],
    );
  }

  /// Prompt réduit à un unique message utilisateur.
  factory AiPrompt.user(String content) {
    return AiPrompt(messages: <AiMessage>[AiMessage.user(content)]);
  }

  /// Messages de la conversation, dans l'ordre.
  final List<AiMessage> messages;

  /// Consignes système concaténées.
  String get systemText {
    return messages
        .where((AiMessage message) => message.role == AiRole.system)
        .map((AiMessage message) => message.content)
        .join('\n\n');
  }

  /// Messages hors consigne système (alternance user / assistant).
  List<AiMessage> get conversationMessages {
    return messages
        .where((AiMessage message) => message.role != AiRole.system)
        .toList(growable: false);
  }

  /// Copie modifiée de ce prompt.
  AiPrompt copyWith({List<AiMessage>? messages}) {
    return AiPrompt(messages: messages ?? this.messages);
  }

  /// Texte intégral du prompt, utilisé pour l'estimation de tokens.
  String get plainText {
    return messages.map((AiMessage message) => message.content).join('\n\n');
  }
}
