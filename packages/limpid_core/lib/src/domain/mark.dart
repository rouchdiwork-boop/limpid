import 'package:limpid_core/src/errors.dart';
import 'package:limpid_core/src/internal/collections.dart';

import 'enums.dart';
import 'ids.dart';

/// A character range inside a block, `[start, end[`.
///
/// Offsets are expressed in UTF-16 code units of the block plain text, which
/// is the convention used by the Flutter editor.
final class MarkRange {
  /// Creates a mark range.
  ///
  /// Throws an [InvalidContentException] when the range is negative or
  /// inverted.
  const MarkRange({required this.start, required this.end})
    : assert(start >= 0, 'start must be non negative'),
      assert(end >= start, 'end must be greater than or equal to start');

  /// Inclusive start offset.
  final int start;

  /// Exclusive end offset.
  final int end;

  /// Number of code units covered by this range.
  int get length => end - start;

  /// Whether this range selects nothing.
  bool get isEmpty => end == start;

  /// Returns a copy of this range moved by [offset] code units.
  MarkRange shift(int offset) =>
      MarkRange(start: start + offset, end: end + offset);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is MarkRange && other.start == start && other.end == end);

  @override
  int get hashCode => Object.hash(MarkRange, start, end);

  @override
  String toString() => 'MarkRange($start, $end)';
}

/// An annotation attached to a range of a block.
///
/// Marks are an additive set: they never conflict with the text and two
/// authors may add marks to the same block concurrently.
final class Mark {
  /// Creates a mark.
  const Mark({
    required this.id,
    required this.blockId,
    required this.type,
    required this.range,
    required this.author,
    required this.createdAt,
    this.body = '',
    this.data = const <String, String>{},
  });

  /// Global identifier of the mark.
  final MarkId id;

  /// Block this mark is anchored to.
  final BlockId blockId;

  /// Nature of the annotation.
  final MarkType type;

  /// Character range covered by the annotation.
  final MarkRange range;

  /// Author who created the mark.
  final AuthorId author;

  /// Creation timestamp.
  final DateTime createdAt;

  /// Free-form body (comment text, AI explanation…).
  final String body;

  /// Additional structured payload.
  final Map<String, String> data;

  /// Whether this mark was produced by the AI assistant.
  bool get isAiGenerated => isAiMarkType(type);

  /// Returns a copy of this mark with the given fields replaced.
  Mark copyWith({
    MarkType? type,
    MarkRange? range,
    AuthorId? author,
    DateTime? createdAt,
    String? body,
    Map<String, String>? data,
  }) {
    return Mark(
      id: id,
      blockId: blockId,
      type: type ?? this.type,
      range: range ?? this.range,
      author: author ?? this.author,
      createdAt: createdAt ?? this.createdAt,
      body: body ?? this.body,
      data: data ?? this.data,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Mark &&
          other.id == id &&
          other.blockId == blockId &&
          other.type == type &&
          other.range == range &&
          other.author == author &&
          other.createdAt == createdAt &&
          other.body == body &&
          mapEquals(other.data, data));

  @override
  int get hashCode => Object.hash(
    Mark,
    id,
    blockId,
    type,
    range,
    author,
    createdAt,
    body,
    Object.hashAllUnordered(
      data.entries.map((e) => Object.hash(e.key, e.value)),
    ),
  );

  @override
  String toString() => 'Mark($id, $type, $range)';
}
