/// Rôle d'un message dans une conversation avec un modèle de langage.
enum AiRole {
  /// Instruction système : posture, garde-fous, format de sortie.
  system,

  /// Message de l'auteur.
  user,

  /// Réponse précédente de l'assistant.
  assistant;

  /// Nom du rôle tel qu'attendu par les API HTTP.
  String get wireName => name;
}

/// Message immuable d'une conversation.
class AiMessage {
  const AiMessage({required this.role, required this.content});

  /// Message système (consignes de posture et de format).
  const AiMessage.system(String this.content) : role = AiRole.system;

  /// Message utilisateur.
  const AiMessage.user(String this.content) : role = AiRole.user;

  /// Message assistant.
  const AiMessage.assistant(String this.content) : role = AiRole.assistant;

  final AiRole role;
  final String content;

  /// Copie modifiée de ce message.
  AiMessage copyWith({AiRole? role, String? content}) {
    return AiMessage(role: role ?? this.role, content: content ?? this.content);
  }

  /// Sérialisation JSON (format commun OpenAI/Anthropic).
  Map<String, String> toJson() => <String, String>{
    'role': role.wireName,
    'content': content,
  };

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }
    return other is AiMessage && other.role == role && other.content == content;
  }

  @override
  int get hashCode => Object.hash(role, content);

  @override
  String toString() => 'AiMessage(${role.wireName})';
}
