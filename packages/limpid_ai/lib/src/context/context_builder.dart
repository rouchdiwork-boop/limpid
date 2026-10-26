import 'package:limpid_ai/src/context/manuscript_context.dart';
import 'package:limpid_ai/src/context/token_estimator.dart';

/// Bloc retenu dans le contexte assemblé.
class ContextEntry {
  /// Crée une entrée de contexte.
  const ContextEntry({
    required this.block,
    required this.text,
    required this.estimatedTokens,
    this.isTruncated = false,
  });

  /// Bloc d'origine.
  final ContextBlock block;

  /// Texte retenu (tronqué si la fenêtre était trop petite).
  final String text;

  /// Volume de tokens estimé pour ce bloc.
  final int estimatedTokens;

  /// Vrai si le texte a été tronqué pour tenir dans la fenêtre.
  final bool isTruncated;
}

/// Contexte assemblé, prêt à être injecté dans un prompt.
class BuiltContext {
  /// Crée un contexte assemblé.
  const BuiltContext({
    required this.text,
    required this.included,
    required this.dropped,
    required this.estimatedTokens,
  });

  /// Contexte assemblé, prêt à insérer dans un prompt.
  final String text;

  /// Blocs retenus, dans l'ordre de priorité.
  final List<ContextEntry> included;

  /// Blocs écartés faute de place.
  final List<ContextBlock> dropped;

  /// Volume de tokens estimé pour l'ensemble du contexte.
  final int estimatedTokens;

  /// Vrai si aucun bloc n'a pu être retenu.
  bool get isEmpty => included.isEmpty;
}

/// Assemble le contexte d'un manuscrit dans une fenêtre de tokens.
///
/// Règle de remplissage : la scène courante passe en premier, puis le chapitre
/// courant et les chapitres voisins, puis la bible, puis les notes globales.
/// Quand la fenêtre est saturée, les chapitres les plus lointains sont
/// écartés ; la scène courante, elle, est tronquée plutôt qu'écartée.
class ContextBuilder {
  /// Crée un assembleur de contexte.
  const ContextBuilder({this.estimator = const HeuristicTokenEstimator()});

  /// Estimateur de tokens utilisé.
  final TokenEstimator estimator;

  /// Assemble le contexte pour une fenêtre de tokens donnée.
  BuiltContext build(ManuscriptContext context, {required int tokenWindow}) {
    if (tokenWindow <= 0) {
      return BuiltContext(
        text: '',
        included: const <ContextEntry>[],
        dropped: context.orderedBlocks,
        estimatedTokens: 0,
      );
    }

    final List<ContextBlock> ordered = context.orderedBlocks;
    final List<ContextEntry> included = <ContextEntry>[];
    final List<ContextBlock> dropped = <ContextBlock>[];
    int remaining = tokenWindow;

    for (final ContextBlock block in ordered) {
      if (remaining <= 0) {
        dropped.add(block);
        continue;
      }
      final int blockTokens = estimator.estimate(block.text);
      if (blockTokens <= remaining) {
        included.add(
          ContextEntry(
            block: block,
            text: block.text,
            estimatedTokens: blockTokens,
          ),
        );
        remaining -= blockTokens;
        continue;
      }
      final String truncated = _truncateToFit(block.text, remaining);
      if (truncated.isEmpty) {
        dropped.add(block);
        continue;
      }
      included.add(
        ContextEntry(
          block: block,
          text: truncated,
          estimatedTokens: estimator.estimate(truncated),
          isTruncated: true,
        ),
      );
      remaining = 0;
    }

    return BuiltContext(
      text: render(included),
      included: included,
      dropped: dropped,
      estimatedTokens: tokenWindow - remaining,
    );
  }

  /// Rend le contexte assemblé en texte.
  String render(List<ContextEntry> entries) {
    final List<String> sections = <String>[
      for (final ContextEntry entry in entries)
        '## ${entry.block.title}\n${entry.text}',
    ];
    return sections.join('\n\n');
  }

  String _truncateToFit(String text, int maxTokens) {
    if (maxTokens <= 0 || text.isEmpty) {
      return '';
    }
    int low = 0;
    int high = text.length;
    while (low < high) {
      final int middle = (low + high + 1) ~/ 2;
      if (estimator.estimate(text.substring(0, middle)) <= maxTokens) {
        low = middle;
      } else {
        high = middle - 1;
      }
    }
    return text.substring(0, low);
  }
}
