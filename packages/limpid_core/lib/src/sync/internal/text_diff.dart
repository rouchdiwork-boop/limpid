import 'package:limpid_core/src/domain/mark.dart';
import 'package:limpid_core/src/sync/text_edit.dart';

/// The kind of a chunk of the diff script.
enum DiffChunkKind { equal, delete, insert }

/// A chunk of the diff script.
final class DiffChunk {
  /// Creates a chunk.
  const DiffChunk(this.kind, this.text);

  /// Nature of the chunk.
  final DiffChunkKind kind;

  /// Text of the chunk.
  final String text;
}

/// A text split into Unicode code points with their UTF-16 offsets.
final class DiffRuneText {
  /// Splits [text] into code points and records their UTF-16 offsets.
  DiffRuneText(this.text) : runes = text.runes.toList(growable: false) {
    offsets = List<int>.filled(runes.length + 1, 0);
    var offset = 0;
    for (var i = 0; i < runes.length; i++) {
      offsets[i] = offset;
      offset += String.fromCharCode(runes[i]).length;
    }
    offsets[runes.length] = offset;
  }

  /// The original text.
  final String text;

  /// The code points of the text.
  final List<int> runes;

  /// UTF-16 offset of every code point, plus the total length.
  late final List<int> offsets;

  /// The index of the code point that holds the UTF-16 [offset].
  ///
  /// An offset that falls inside a surrogate pair belongs to the code point
  /// that follows it: a range never splits a code point.
  int runeIndexOf(int offset) {
    var low = 0;
    var high = runes.length;
    while (low < high) {
      final int middle = (low + high) ~/ 2;
      if (offsets[middle] < offset) {
        low = middle + 1;
      } else {
        high = middle;
      }
    }
    return low;
  }
}

/// The mapper of the ranges of a reference text onto another text.
///
/// The mapper holds the diff of the two texts. A range of the reference is
/// mapped through it: the code points that survived keep their place, and the
/// code points that disappeared leave a hole the range steps over.
///
/// The range therefore follows the words it covers: a rewrite before it moves
/// it, a rewrite after it leaves it alone, and a rewrite inside it truncates
/// it. A range whose code points all disappeared becomes an empty range at
/// the place of the hole.
final class RangeMapper {
  /// Creates the mapper of the ranges of [reference] onto [text].
  RangeMapper({required this.reference, required this.text});

  /// The text the ranges were computed on.
  final String reference;

  /// The text the ranges are mapped onto.
  final String text;

  /// The reference, split into code points.
  late final DiffRuneText _base = DiffRuneText(reference);

  /// The text, split into code points.
  late final DiffRuneText _target = DiffRuneText(text);

  /// The diff of the two texts, computed once.
  late final List<DiffChunk> _chunks = reference == text
      ? const <DiffChunk>[]
      : diffRuneChunks(_base.runes, _target.runes);

  /// Maps [range] from the reference onto the text.
  ///
  /// The returned range is expressed in the UTF-16 code units of the text.
  MarkRange map(MarkRange range) {
    if (reference == text) return range;
    final int start = _base.runeIndexOf(range.start);
    final int end = _base.runeIndexOf(range.end);
    final _MappedRange mapped = _walk(start: start, end: end);
    final int from = mapped.from ?? mapped.endOfReference;
    final int to = mapped.to ?? mapped.endOfReference;
    return MarkRange(
      start: _target.offsets[from],
      end: _target.offsets[to < from ? from : to],
    );
  }

  /// Walks the diff and maps the code points `[start, end[` of the reference.
  _MappedRange _walk({required int start, required int end}) {
    var basePosition = 0;
    var targetPosition = 0;
    var endOfReference = 0;
    int? from;
    int? to;

    for (final DiffChunk chunk in _chunks) {
      if (chunk.kind == DiffChunkKind.insert) {
        targetPosition += chunk.text.runes.length;
        continue;
      }
      final int length = chunk.text.runes.length;
      final bool survives = chunk.kind == DiffChunkKind.equal;
      if (from == null &&
          start >= basePosition &&
          start < basePosition + length) {
        from = survives
            ? targetPosition + (start - basePosition)
            : targetPosition;
      }
      if (to == null && end > basePosition && end <= basePosition + length) {
        to = survives ? targetPosition + (end - basePosition) : targetPosition;
      }
      basePosition += length;
      if (survives) targetPosition += length;
      if (basePosition == _base.runes.length) endOfReference = targetPosition;
    }

    return _MappedRange(from: from, to: to, endOfReference: endOfReference);
  }
}

/// The result of the walk of a diff: the place of the two ends of a range.
final class _MappedRange {
  /// Creates the result of the walk.
  const _MappedRange({
    required this.from,
    required this.to,
    required this.endOfReference,
  });

  /// The place of the first code point of the range, `null` when it is gone.
  final int? from;

  /// The place just after the last code point of the range, `null` when it is
  /// gone.
  final int? to;

  /// The place of the end of the reference in the target.
  final int endOfReference;
}

/// Computes the diff of two code point sequences with the Myers algorithm.
///
/// The produced script is minimal: it never splits a code point and it keeps
/// the common prefix and suffix of both sequences outside of the edits.
List<DiffChunk> diffRuneChunks(List<int> left, List<int> right) {
  final n = left.length;
  final m = right.length;
  if (n == 0 && m == 0) return const <DiffChunk>[];
  if (n == 0) {
    return <DiffChunk>[
      DiffChunk(DiffChunkKind.insert, String.fromCharCodes(right)),
    ];
  }
  if (m == 0) {
    return <DiffChunk>[
      DiffChunk(DiffChunkKind.delete, String.fromCharCodes(left)),
    ];
  }

  final max = n + m;
  final offset = max;
  final v = List<int>.filled(2 * max + 1, 0);
  final trace = <List<int>>[];

  for (var d = 0; d <= max; d++) {
    trace.add(List<int>.of(v));
    for (var k = -d; k <= d; k += 2) {
      int x;
      if (k == -d || (k != d && v[k - 1 + offset] < v[k + 1 + offset])) {
        x = v[k + 1 + offset];
      } else {
        x = v[k - 1 + offset] + 1;
      }
      var y = x - k;
      while (x < n && y < m && left[x] == right[y]) {
        x++;
        y++;
      }
      v[k + offset] = x;
      if (x >= n && y >= m) {
        return _backtrack(trace, d, left, right, offset);
      }
    }
  }
  throw StateError('The diff of two strings must always terminate.');
}

/// Rebuilds the diff script from the trace of the Myers algorithm.
List<DiffChunk> _backtrack(
  List<List<int>> trace,
  int depth,
  List<int> left,
  List<int> right,
  int offset,
) {
  final reversed = <DiffChunk>[];
  var x = left.length;
  var y = right.length;

  for (var d = depth; d > 0; d--) {
    final v = trace[d];
    final k = x - y;
    final int previousK;
    if (k == -d || (k != d && v[k - 1 + offset] < v[k + 1 + offset])) {
      previousK = k + 1;
    } else {
      previousK = k - 1;
    }
    final previousX = v[previousK + offset];
    final previousY = previousX - previousK;
    while (x > previousX && y > previousY) {
      x--;
      y--;
      reversed.add(
        DiffChunk(DiffChunkKind.equal, String.fromCharCode(left[x])),
      );
    }
    if (x == previousX) {
      y--;
      reversed.add(
        DiffChunk(DiffChunkKind.insert, String.fromCharCode(right[y])),
      );
    } else {
      x--;
      reversed.add(
        DiffChunk(DiffChunkKind.delete, String.fromCharCode(left[x])),
      );
    }
    x = previousX;
    y = previousY;
  }
  while (x > 0 && y > 0) {
    x--;
    y--;
    reversed.add(DiffChunk(DiffChunkKind.equal, String.fromCharCode(left[x])));
  }
  while (x > 0) {
    x--;
    reversed.add(DiffChunk(DiffChunkKind.delete, String.fromCharCode(left[x])));
  }
  while (y > 0) {
    y--;
    reversed.add(
      DiffChunk(DiffChunkKind.insert, String.fromCharCode(right[y])),
    );
  }
  return _groupChunks(reversed.reversed.toList());
}

/// Groups consecutive chunks of the same kind into larger chunks.
List<DiffChunk> _groupChunks(List<DiffChunk> chunks) {
  final result = <DiffChunk>[];
  DiffChunkKind? kind;
  StringBuffer? buffer;
  for (final chunk in chunks) {
    if (kind != chunk.kind) {
      if (kind != null) result.add(DiffChunk(kind, buffer!.toString()));
      kind = chunk.kind;
      buffer = StringBuffer();
    }
    buffer!.write(chunk.text);
  }
  if (kind != null) result.add(DiffChunk(kind, buffer!.toString()));
  return result;
}

/// Converts a diff script into the list of edits it describes.
///
/// The offsets of the produced edits are expressed in UTF-16 code units of
/// [base].
List<TextEdit> runeChunksToEdits(List<DiffChunk> chunks, DiffRuneText base) {
  final edits = <TextEdit>[];
  var position = 0;
  for (var i = 0; i < chunks.length; i++) {
    final chunk = chunks[i];
    if (chunk.kind == DiffChunkKind.equal) {
      position += chunk.text.runes.length;
    } else if (chunk.kind == DiffChunkKind.delete) {
      final end = position + chunk.text.runes.length;
      var replacement = '';
      final next = i + 1;
      if (next < chunks.length && chunks[next].kind == DiffChunkKind.insert) {
        replacement = chunks[next].text;
        i = next;
      }
      edits.add(
        TextEdit(
          start: base.offsets[position],
          end: base.offsets[end],
          replacement: replacement,
        ),
      );
      position = end;
    } else {
      edits.add(
        TextEdit(
          start: base.offsets[position],
          end: base.offsets[position],
          replacement: chunk.text,
        ),
      );
    }
  }
  return edits;
}
