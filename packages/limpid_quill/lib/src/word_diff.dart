import 'package:flutter/foundation.dart';

/// The nature of a segment of a text difference.
enum LimpidDiffKind {
  /// The text is present in both versions.
  unchanged,

  /// The text was added by the suggestion.
  insertion,

  /// The text was removed by the suggestion.
  deletion,
}

/// A segment of a text difference.
@immutable
class LimpidDiffSegment {
  /// Creates a difference segment.
  const LimpidDiffSegment({required this.text, required this.kind});

  /// The text of the segment.
  final String text;

  /// The nature of the segment.
  final LimpidDiffKind kind;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is LimpidDiffSegment && other.text == text && other.kind == kind);

  @override
  int get hashCode => Object.hash(text, kind);

  @override
  String toString() => 'LimpidDiffSegment($kind, "$text")';
}

/// Computes the difference between [original] and [suggestion].
///
/// The two texts are compared word by word — the whitespace and the
/// punctuation are kept as their own tokens — and the result is a list of
/// segments that rebuild the suggestion exactly.
List<LimpidDiffSegment> diffWords(String original, String suggestion) {
  final List<String> before = _tokenize(original);
  final List<String> after = _tokenize(suggestion);
  final List<List<int>> table = _longestCommonSubsequence(before, after);

  final List<LimpidDiffSegment> segments = <LimpidDiffSegment>[];
  int i = 0;
  int j = 0;
  while (i < before.length || j < after.length) {
    if (i < before.length && j < after.length && before[i] == after[j]) {
      _append(segments, after[j], LimpidDiffKind.unchanged);
      i++;
      j++;
      continue;
    }
    // The deletion comes first: the reader sees the original passage, then
    // the text that replaces it.
    final bool prefersDeletion =
        j >= after.length ||
        (i < before.length && table[i + 1][j] >= table[i][j + 1]);
    if (prefersDeletion) {
      _append(segments, before[i], LimpidDiffKind.deletion);
      i++;
      continue;
    }
    _append(segments, after[j], LimpidDiffKind.insertion);
    j++;
  }
  return segments;
}

/// Merges the consecutive segments of the same kind.
void _append(
  List<LimpidDiffSegment> segments,
  String text,
  LimpidDiffKind kind,
) {
  if (segments.isNotEmpty && segments.last.kind == kind) {
    final LimpidDiffSegment last = segments.removeLast();
    segments.add(LimpidDiffSegment(text: last.text + text, kind: kind));
    return;
  }
  segments.add(LimpidDiffSegment(text: text, kind: kind));
}

/// Splits a text into words, whitespace and punctuation.
List<String> _tokenize(String text) {
  final RegExp pattern = RegExp(r'\s+|\w+|[^\s\w]', unicode: true);
  return pattern
      .allMatches(text)
      .map((RegExpMatch match) => match.group(0)!)
      .toList(growable: false);
}

/// Builds the table of the lengths of the longest common subsequences.
///
/// `table[i][j]` holds the length of the longest common subsequence of the
/// suffixes `before[i…]` and `after[j…]`.
List<List<int>> _longestCommonSubsequence(
  List<String> before,
  List<String> after,
) {
  final List<List<int>> table = List<List<int>>.generate(
    before.length + 1,
    (int i) => List<int>.filled(after.length + 1, 0),
    growable: false,
  );
  for (int i = before.length - 1; i >= 0; i--) {
    for (int j = after.length - 1; j >= 0; j--) {
      table[i][j] = before[i] == after[j]
          ? table[i + 1][j + 1] + 1
          : (table[i + 1][j] > table[i][j + 1]
                ? table[i + 1][j]
                : table[i][j + 1]);
    }
  }
  return table;
}
