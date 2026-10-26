/// A replacement of the base range `[start, end[` by [replacement].
///
/// Offsets are expressed in UTF-16 code units, the convention used by the
/// Flutter editor.
final class TextEdit {
  /// Creates a text edit.
  const TextEdit({
    required this.start,
    required this.end,
    required this.replacement,
  });

  /// Inclusive start offset in the base text.
  final int start;

  /// Exclusive end offset in the base text.
  final int end;

  /// The text that replaces the base range.
  final String replacement;

  /// Number of base code units covered by this edit.
  int get length => end - start;

  /// Whether this edit does not touch the base text.
  bool get isInsertion => start == end;

  /// Whether this edit removes base text.
  bool get isDeletion => replacement.isEmpty;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is TextEdit &&
          other.start == start &&
          other.end == end &&
          other.replacement == replacement);

  @override
  int get hashCode => Object.hash(TextEdit, start, end, replacement);

  @override
  String toString() => 'TextEdit($start, $end, "$replacement")';
}

/// Applies [edits] to [base] and returns the resulting text.
///
/// Throws an [ArgumentError] when the edits overlap.
String applyTextEdits(String base, List<TextEdit> edits) {
  if (edits.isEmpty) return base;
  final sorted = [...edits]
    ..sort((a, b) {
      final byStart = a.start.compareTo(b.start);
      if (byStart != 0) return byStart;
      return a.end.compareTo(b.end);
    });
  final buffer = StringBuffer();
  var position = 0;
  for (final edit in sorted) {
    if (edit.start < position) {
      throw ArgumentError(
        'Overlapping text edits are not applicable: $edit at $position.',
      );
    }
    buffer.write(base.substring(position, edit.start));
    buffer.write(edit.replacement);
    position = edit.end;
  }
  buffer.write(base.substring(position));
  return buffer.toString();
}
