import 'package:limpid_ai/limpid_ai.dart';
import 'package:test/test.dart';

void main() {
  /// Bloc de contexte dont la taille est maîtrisée (4 caractères par token).
  ContextBlock block(
    String id,
    ContextPriority priority,
    int tokenCount, {
    int distance = 0,
  }) {
    return ContextBlock(
      id: id,
      title: id,
      text: 'x' * (tokenCount * 4),
      priority: priority,
      distance: distance,
    );
  }

  ManuscriptContext buildContext() {
    return ManuscriptContext(
      currentScene: block('scene', ContextPriority.currentScene, 100),
      chapters: <ContextBlock>[
        block('chapitre-proche', ContextPriority.chapter, 100, distance: 1),
        block('chapitre-lointain', ContextPriority.chapter, 200, distance: 9),
      ],
      bible: <ContextBlock>[block('bible', ContextPriority.bible, 50)],
      globalNotes: <ContextBlock>[block('global', ContextPriority.global, 50)],
    );
  }

  group('ContextBuilder', () {
    test('respecte la priorité : scène, chapitre, bible, global', () {
      final BuiltContext context = const ContextBuilder().build(
        buildContext(),
        tokenWindow: 1000,
      );

      expect(
        context.included.map((ContextEntry entry) => entry.block.id),
        <String>[
          'scene',
          'chapitre-proche',
          'chapitre-lointain',
          'bible',
          'global',
        ],
      );
      expect(context.dropped, isEmpty);
    });

    test('écarte les chapitres lointains quand la fenêtre est saturée', () {
      final BuiltContext context = const ContextBuilder().build(
        buildContext(),
        tokenWindow: 200,
      );

      expect(
        context.included.map((ContextEntry entry) => entry.block.id),
        <String>['scene', 'chapitre-proche'],
      );
      expect(
        context.dropped.map((ContextBlock bloc) => bloc.id),
        containsAll(<String>['chapitre-lointain', 'bible', 'global']),
      );
      expect(context.estimatedTokens, lessThanOrEqualTo(200));
      expect(context.text, contains('## scene'));
    });

    test('tronque un bloc trop long plutôt que de l\'écarter', () {
      final BuiltContext context = const ContextBuilder().build(
        buildContext(),
        tokenWindow: 300,
      );

      final ContextEntry truncated = context.included.firstWhere(
        (ContextEntry entry) => entry.block.id == 'chapitre-lointain',
      );
      expect(truncated.isTruncated, isTrue);
      expect(truncated.text.length, 400);
      expect(context.estimatedTokens, lessThanOrEqualTo(300));
    });

    test('renvoie un contexte vide pour une fenêtre nulle', () {
      final BuiltContext context = const ContextBuilder().build(
        buildContext(),
        tokenWindow: 0,
      );

      expect(context.isEmpty, isTrue);
      expect(context.text, isEmpty);
      expect(context.dropped, hasLength(5));
    });

    test('classe les chapitres du plus proche au plus lointain', () {
      const ContextBuilder builder = ContextBuilder();
      final BuiltContext context = builder.build(
        buildContext(),
        tokenWindow: 250,
      );

      final List<String> included = context.included
          .map((ContextEntry entry) => entry.block.id)
          .toList();
      expect(
        included.indexOf('chapitre-proche'),
        lessThan(included.indexOf('chapitre-lointain')),
      );
    });
  });

  group('TokenEstimator', () {
    test('estime quatre caractères par token', () {
      const HeuristicTokenEstimator estimator = HeuristicTokenEstimator();
      expect(estimator.estimate(''), 0);
      expect(estimator.estimate('abcd'), 1);
      expect(estimator.estimate('abcde'), 2);
    });
  });
}
