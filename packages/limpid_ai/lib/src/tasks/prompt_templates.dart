import 'package:limpid_ai/src/tasks/prompt_templates_analysis.dart';
import 'package:limpid_ai/src/tasks/prompt_templates_characters.dart';
import 'package:limpid_ai/src/tasks/prompt_templates_planning.dart';
import 'package:limpid_ai/src/tasks/prompt_templates_rag.dart';
import 'package:limpid_ai/src/tasks/prompt_templates_text.dart';

/// Point d'entrée unique des modèles de prompt.
///
/// Les textes sont regroupés par domaine dans des classes dédiées ; cette
/// façade les expose sous un seul nom pour que le registre des tâches n'ait
/// qu'une dépendance à connaître.
abstract final class PromptTemplates {
  const PromptTemplates._();

  /// Modèles des tâches de manipulation de texte.
  static const PromptTemplatesText text = PromptTemplatesText();

  /// Modèles des tâches de planification.
  static const PromptTemplatesPlanning planning = PromptTemplatesPlanning();

  /// Modèles des tâches de personnages.
  static const PromptTemplatesCharacters characters =
      PromptTemplatesCharacters();

  /// Modèles des tâches d'analyse.
  static const PromptTemplatesAnalysis analysis = PromptTemplatesAnalysis();

  /// Modèles des tâches adossées au manuscrit.
  static const PromptTemplatesRag rag = PromptTemplatesRag();
}
