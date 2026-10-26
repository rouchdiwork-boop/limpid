/// Clés stables des tâches IA du registre.
///
/// Ces clés sont utilisées comme identifiants de fonctionnalité dans les
/// compteurs de quota et dans les journaux : elles ne doivent pas changer.
abstract final class AiTaskKeys {
  /// Réécriture inline (A1).
  static const String rewriteInline = 'rewrite_inline';

  /// Continuation assistée (A2).
  static const String continueText = 'continue_text';

  /// Génération de plan (A3).
  static const String generateOutline = 'generate_outline';

  /// Génération de personnages et fiches (A4).
  static const String generateCharacters = 'generate_characters';

  /// Génération de monde et lieux (A5).
  static const String generateWorld = 'generate_world';

  /// Résumé de scène ou de chapitre (A6).
  static const String summarize = 'summarize';

  /// Interrogation du manuscrit par RAG (A7).
  static const String queryBook = 'query_book';

  /// Contrôle de cohérence (A8).
  static const String checkConsistency = 'check_consistency';

  /// Analyse de style et profil de voix (A9).
  static const String analyzeStyle = 'analyze_style';

  /// Détection de clichés et de répétitions (A10).
  static const String detectCliches = 'detect_cliches';

  /// Génération de couverture (A11).
  static const String generateCover = 'generate_cover';

  /// Beat sheet (A12).
  static const String generateBeatSheet = 'generate_beat_sheet';

  /// Analyse de lisibilité (A13).
  static const String analyzeReadability = 'analyze_readability';

  /// Traduction assistée (A14).
  static const String translateText = 'translate_text';
}
