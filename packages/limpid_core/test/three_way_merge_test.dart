import 'dart:math' as math;

import 'package:limpid_core/limpid_core.dart';
import 'package:test/test.dart';

void main() {
  group('diffText', () {
    test('returns no edit for identical texts', () {
      expect(diffText('hello', 'hello'), isEmpty);
    });

    test('detects a pure insertion', () {
      final edits = diffText('ab', 'axb');
      expect(edits, hasLength(1));
      expect(edits.single.start, 1);
      expect(edits.single.end, 1);
      expect(edits.single.replacement, 'x');
    });

    test('detects a pure deletion', () {
      final edits = diffText('axb', 'ab');
      expect(edits, hasLength(1));
      expect(edits.single.start, 1);
      expect(edits.single.end, 2);
      expect(edits.single.replacement, isEmpty);
    });

    test('detects a replacement', () {
      final edits = diffText('cat', 'dog');
      expect(edits, hasLength(1));
      expect(edits.single.start, 0);
      expect(edits.single.end, 3);
      expect(edits.single.replacement, 'dog');
    });

    test('rebuilds the target text for random inputs', () {
      final random = math.Random(20261025);
      for (var iteration = 0; iteration < 500; iteration++) {
        final base = _randomText(random);
        final other = _randomText(random);
        final edits = diffText(base, other);
        expect(
          applyTextEdits(base, edits),
          other,
          reason: 'base="$base" other="$other"',
        );
      }
    });

    test('rebuilds the target text when the base is mutated', () {
      final random = math.Random(7);
      for (var iteration = 0; iteration < 200; iteration++) {
        final base = _randomText(random);
        final other = _mutate(random, base);
        final edits = diffText(base, other);
        expect(applyTextEdits(base, edits), other);
      }
    });
  });

  group('mergeThreeWay', () {
    test('returns the other side when one side did not change', () {
      expect(
        mergeThreeWay(base: 'hello', left: 'hello', right: 'hello world'),
        'hello world',
      );
      expect(
        mergeThreeWay(base: 'hello', left: 'hello world', right: 'hello'),
        'hello world',
      );
    });

    test('returns the shared text when both sides changed identically', () {
      expect(
        mergeThreeWay(base: 'hello', left: 'hello world', right: 'hello world'),
        'hello world',
      );
    });

    test('merges disjoint edits', () {
      final merged = mergeThreeWay(
        base: 'The quick brown fox',
        left: 'The quick red fox',
        right: 'The slow brown fox',
      );
      expect(merged, 'The slow red fox');
    });

    test('merges two insertions at the same place', () {
      final merged = mergeThreeWay(base: 'ab', left: 'aXb', right: 'aYb');
      expect(merged, contains('X'));
      expect(merged, contains('Y'));
      expect(merged.startsWith('a'), isTrue);
      expect(merged.endsWith('b'), isTrue);
    });

    test('is symmetric in its two variants', () {
      const base = 'The quick brown fox jumps';
      const left = 'The quick red fox jumps';
      const right = 'A slow brown fox jumps';
      expect(
        mergeThreeWay(base: base, left: left, right: right),
        mergeThreeWay(base: base, left: right, right: left),
      );
    });

    test('only depends on the set of variants', () {
      const base = 'alpha beta gamma';
      const first = 'alpha BETA gamma';
      const second = 'ALPHA beta gamma';
      final forward = mergeVariants(
        base: base,
        variants: <MergeVariant>[
          const MergeVariant(text: first),
          const MergeVariant(text: second),
        ],
      );
      final backward = mergeVariants(
        base: base,
        variants: <MergeVariant>[
          const MergeVariant(text: second),
          const MergeVariant(text: first),
        ],
      );
      expect(forward, backward);
    });

    test('keeps both texts when they conflict on the same range', () {
      final merged = mergeThreeWay(base: 'abc', left: 'aXc', right: 'aYc');
      expect(merged, contains('X'));
      expect(merged, contains('Y'));
    });

    test('is symmetric for random inputs', () {
      final random = math.Random(4242);
      for (var iteration = 0; iteration < 300; iteration++) {
        final base = _randomText(random);
        final left = _mutate(random, base);
        final right = _mutate(random, base);
        expect(
          mergeThreeWay(base: base, left: left, right: right),
          mergeThreeWay(base: base, left: right, right: left),
          reason: 'base="$base" left="$left" right="$right"',
        );
      }
    });

    test('keeps the common prefix of both variants', () {
      final random = math.Random(99);
      for (var iteration = 0; iteration < 500; iteration++) {
        final base = _randomText(random);
        final left = _mutate(random, base);
        final right = _mutate(random, base);
        final merged = mergeThreeWay(base: base, left: left, right: right);
        final commonPrefix = _commonPrefixLength(left, right);
        expect(
          merged.substring(0, commonPrefix),
          left.substring(0, commonPrefix),
        );
      }
    });

    test('is idempotent when applied twice', () {
      const base = 'abc def';
      const left = 'abc X def';
      const right = 'abc Y def';
      final once = mergeThreeWay(base: base, left: left, right: right);
      final twice = mergeThreeWay(base: base, left: once, right: once);
      expect(twice, once);
    });
  });

  group('mergeVariants', () {
    test('orders conflicts by priority', () {
      final merged = mergeVariants(
        base: 'abc',
        variants: <MergeVariant>[
          const MergeVariant(text: 'aXc', priority: 1, tiebreak: 'a'),
          const MergeVariant(text: 'aYc', priority: 2, tiebreak: 'b'),
        ],
      );
      expect(merged.indexOf('X'), lessThan(merged.indexOf('Y')));
    });

    test('returns the base when every variant equals it', () {
      expect(
        mergeVariants(
          base: 'same',
          variants: <MergeVariant>[
            const MergeVariant(text: 'same'),
            const MergeVariant(text: 'same'),
          ],
        ),
        'same',
      );
    });

    test('returns the base when there is no variant', () {
      expect(
        mergeVariants(base: 'same', variants: const <MergeVariant>[]),
        'same',
      );
    });
  });
}

/// Builds a short random text.
String _randomText(math.Random random) {
  const alphabet = 'abcdefghij klmnop';
  final length = random.nextInt(12);
  final buffer = StringBuffer();
  for (var i = 0; i < length; i++) {
    buffer.write(alphabet[random.nextInt(alphabet.length)]);
  }
  return buffer.toString();
}

/// Applies a random mutation to [text].
String _mutate(math.Random random, String text) {
  if (text.isEmpty) return 'x';
  final index = random.nextInt(text.length);
  return switch (random.nextInt(3)) {
    0 => '${text.substring(0, index)}${text.substring(index + 1)}',
    1 => '${text.substring(0, index)}z${text.substring(index)}',
    _ => '${text.substring(0, index)}z${text.substring(index + 1)}',
  };
}

/// Length of the longest common prefix of [a] and [b].
int _commonPrefixLength(String a, String b) {
  final limit = a.length < b.length ? a.length : b.length;
  var index = 0;
  while (index < limit && a.codeUnitAt(index) == b.codeUnitAt(index)) {
    index++;
  }
  return index;
}
