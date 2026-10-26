import 'package:limpid_ai/src/model/ai_task.dart';

/// Rendu des modèles de prompt.
///
/// Les emplacements sont de la forme `{{cle}}`. Un emplacement non
/// renseigné provoque une erreur : un prompt incomplet part silencieusement
/// dans un modèle, ce qui est pire qu'un échec explicite.
class PromptRenderer {
  const PromptRenderer._();

  static final RegExp _placeholderPattern = RegExp(r'\{\{[a-zA-Z0-9_]+\}\}');

  /// Rendu un modèle avec les valeurs fournies.
  ///
  /// Lève [ArgumentError] si un emplacement reste non renseigné.
  static String render(String template, Map<String, String> values) {
    String result = template;
    for (final MapEntry<String, String> entry in values.entries) {
      result = result.replaceAll('{{${entry.key}}}', entry.value);
    }
    final RegExpMatch? leftover = _placeholderPattern.firstMatch(result);
    if (leftover != null) {
      throw ArgumentError.value(
        leftover.group(0),
        'template',
        'Emplacement de modèle non renseigné : ${leftover.group(0)}',
      );
    }
    return result;
  }

  /// Rendu le modèle utilisateur d'une tâche.
  static String renderUser(AiTask task, Map<String, String> values) {
    return render(task.userTemplate, values);
  }

  /// Liste les emplacements attendus par un modèle.
  static List<String> placeholdersOf(String template) {
    return _placeholderPattern
        .allMatches(template)
        .map((RegExpMatch match) => match.group(0)!)
        .toList(growable: false);
  }
}
