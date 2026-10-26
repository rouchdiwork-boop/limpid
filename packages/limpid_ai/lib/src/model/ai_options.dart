import 'package:limpid_ai/src/model/ai_provider_kind.dart';

/// Options d'un appel IA (modèle, budget de sortie, température, en-têtes).
class AiRequestOptions {
  /// Options par défaut.
  const AiRequestOptions({
    this.model,
    this.maxTokens,
    this.temperature,
    this.omitTemperature = false,
    this.timeout = const Duration(seconds: 120),
    this.extraHeaders = const <String, String>{},
  });

  /// Modèle utilisé, à la place du modèle recommandé par la tâche.
  final String? model;

  /// Plafond de tokens de sortie.
  final int? maxTokens;

  /// Température d'échantillonnage.
  final double? temperature;

  /// Force l'omission du paramètre `temperature` dans la requête.
  ///
  /// Certains modèles à raisonnement n'acceptent plus ce paramètre.
  final bool omitTemperature;

  /// Délai maximal d'attente de la réponse (en-têtes).
  final Duration timeout;

  /// En-têtes HTTP additionnels (jamais de secret : la clé passe par le
  /// magasin de clés `AiCredentialStore`).
  final Map<String, String> extraHeaders;

  /// Copie modifiée de ces options.
  AiRequestOptions copyWith({
    String? model,
    int? maxTokens,
    double? temperature,
    bool? omitTemperature,
    Duration? timeout,
    Map<String, String>? extraHeaders,
  }) {
    return AiRequestOptions(
      model: model ?? this.model,
      maxTokens: maxTokens ?? this.maxTokens,
      temperature: temperature ?? this.temperature,
      omitTemperature: omitTemperature ?? this.omitTemperature,
      timeout: timeout ?? this.timeout,
      extraHeaders: extraHeaders ?? this.extraHeaders,
    );
  }
}

/// Actions de réécriture inline (fonctionnalité A1).
enum AiInlineAction {
  /// Développer le passage, enrichir la matière sans changer le sens.
  expand,

  /// Raccourcir le passage, supprimer les superfluités.
  shorten,

  /// Simplifier la formulation, alléger la syntaxe.
  simplify,

  /// Modifier le ton (tenseur, registre, rythme).
  changeTone,

  /// Traduire le passage.
  translate;

  /// Nom stable de l'action.
  String get wireName => name;

  /// Consigne associée, en français.
  String get instruction {
    switch (this) {
      case AiInlineAction.expand:
        return 'Développe ce passage : ajoute de la matière concrète '
            '(détails sensoriels, gestes, dialogue) sans changer '
            'la trajectoire de la scène.';
      case AiInlineAction.shorten:
        return 'Raccourcis ce passage : supprime les redites, '
            'les adjectifs inutiles et les formulations postponees, '
            'sans perdre d’information utile.';
      case AiInlineAction.simplify:
        return 'Simplifie ce passage : phrases plus courtes, '
            'vocabulaire courant, syntaxe directe, sans appauvrir '
            'la nuance.';
      case AiInlineAction.changeTone:
        return 'Réécris ce passage dans le ton demandé, '
            'en conservant le fond, les faits et le point de vue.';
      case AiInlineAction.translate:
        return 'Traduis ce passage dans la langue cible, '
            'en conservant le registre, le rythme et les noms propres.';
    }
  }
}

/// Demande de réécriture inline.
class AiInlineRequest {
  const AiInlineRequest({
    required this.action,
    required this.text,
    this.tone,
    this.targetLanguage = 'français',
    this.context,
    this.instruction,
  });

  /// Action demandée.
  final AiInlineAction action;

  /// Texte source à réécrire.
  final String text;

  /// Ton visé, pour [AiInlineAction.changeTone].
  final String? tone;

  /// Langue cible, pour [AiInlineAction.translate].
  final String targetLanguage;

  /// Contexte narratif (scène, chapitre, bible).
  final String? context;

  /// Consigne libre ajoutée par l'auteur.
  final String? instruction;

  /// Copie modifiée de cette demande.
  AiInlineRequest copyWith({
    AiInlineAction? action,
    String? text,
    String? tone,
    String? targetLanguage,
    String? context,
    String? instruction,
  }) {
    return AiInlineRequest(
      action: action ?? this.action,
      text: text ?? this.text,
      tone: tone ?? this.tone,
      targetLanguage: targetLanguage ?? this.targetLanguage,
      context: context ?? this.context,
      instruction: instruction ?? this.instruction,
    );
  }
}

/// Demande d'interrogation du manuscrit (« interroge ton livre »).
class AiQueryRequest {
  const AiQueryRequest({
    required this.question,
    this.topK = 6,
    this.minScore = 0.05,
    this.scope,
  });

  /// Question posée par l'auteur.
  final String question;

  /// Nombre maximal de passages retenus.
  final int topK;

  /// Score de similarité minimal d'un passage retenu.
  final double minScore;

  /// Filtre optionnel (identifiant de projet, de tome, de personnage).
  final String? scope;

  /// Copie modifiée de cette demande.
  AiQueryRequest copyWith({
    String? question,
    int? topK,
    double? minScore,
    String? scope,
  }) {
    return AiQueryRequest(
      question: question ?? this.question,
      topK: topK ?? this.topK,
      minScore: minScore ?? this.minScore,
      scope: scope ?? this.scope,
    );
  }
}

/// Étiquettes de gouvernance d'un appel IA (feature, utilisateur, fournisseur).
class AiCallTag {
  const AiCallTag({
    required this.feature,
    required this.userId,
    this.taskKey,
    this.provider = AiProviderKind.anthropic,
  });

  /// Fonctionnalité produit à l'origine de l'appel (ex. `rewrite_inline`).
  final String feature;

  /// Identifiant de l'auteur (compteur de quota).
  final String userId;

  /// Clé de la tâche IA, si l'appel correspond à une tâche du registre.
  final String? taskKey;

  /// Fournisseur utilisée.
  final AiProviderKind provider;

  /// Copie modifiée de ces étiquettes.
  AiCallTag copyWith({
    String? feature,
    String? userId,
    String? taskKey,
    AiProviderKind? provider,
  }) {
    return AiCallTag(
      feature: feature ?? this.feature,
      userId: userId ?? this.userId,
      taskKey: taskKey ?? this.taskKey,
      provider: provider ?? this.provider,
    );
  }
}
