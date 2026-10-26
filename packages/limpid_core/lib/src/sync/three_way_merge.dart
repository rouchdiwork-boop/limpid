import 'dart:math' as math;

import 'package:limpid_core/src/sync/internal/text_diff.dart';
import 'package:limpid_core/src/sync/text_edit.dart';

/// A candidate version of a text, with the priority used to order conflicts.
///
/// The CRDT engine builds variants with the Lamport timestamp and the author
/// identifier, which makes the merge order deterministic on every replica.
final class MergeVariant {
  /// Creates a merge variant.
  const MergeVariant({
    required this.text,
    this.priority = 0,
    this.tiebreak = '',
  });

  /// The candidate text.
  final String text;

  /// Higher priorities win a conflict.
  final int priority;

  /// Secondary deterministic tie-break, typically the author identifier.
  final String tiebreak;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is MergeVariant &&
          other.text == text &&
          other.priority == priority &&
          other.tiebreak == tiebreak);

  @override
  int get hashCode => Object.hash(MergeVariant, text, priority, tiebreak);

  @override
  String toString() => 'MergeVariant($priority, $tiebreak)';
}

/// Computes the edits that turn [base] into [other].
///
/// The diff is minimal: it is computed on Unicode code points with the Myers
/// algorithm, and the common prefix and suffix of both texts are never part
/// of an edit.
List<TextEdit> diffText(String base, String other) {
  if (base == other) return const <TextEdit>[];
  final baseText = DiffRuneText(base);
  final otherText = DiffRuneText(other);
  final chunks = diffRuneChunks(baseText.runes, otherText.runes);
  return runeChunksToEdits(chunks, baseText);
}

/// Merges two concurrent versions of a text that both derive from [base].
///
/// The merge is a true 3-way merge: the parts both authors agree on are kept
/// untouched and the diverging parts are combined with the longest common
/// prefix and suffix rule. The function is symmetric in [left] and [right]:
/// swapping them never changes the result.
String mergeThreeWay({
  required String base,
  required String left,
  required String right,
}) {
  return mergeVariants(
    base: base,
    variants: <MergeVariant>[
      MergeVariant(text: left),
      MergeVariant(text: right),
    ],
  );
}

/// Merges several concurrent versions of a text that all derive from [base].
///
/// The result only depends on the *set* of variants and on [base], never on
/// the order in which they are supplied: two replicas holding the same
/// operations always compute the same text.
String mergeVariants({
  required String base,
  required List<MergeVariant> variants,
}) {
  if (variants.isEmpty) return base;
  final sorted = [...variants]..sort(_compareVariants);
  if (sorted.every((variant) => variant.text == base)) return base;

  final edits = sorted
      .map((variant) => diffText(base, variant.text))
      .toList(growable: false);
  final clusters = _clusterEdits(edits);
  final buffer = StringBuffer();
  var position = 0;
  for (final cluster in clusters) {
    final start = cluster.start;
    final end = cluster.end;
    buffer.write(base.substring(position, start));
    buffer.write(_resolveCluster(base, cluster, sorted));
    position = end;
  }
  buffer.write(base.substring(position));
  return buffer.toString();
}

/// Compares two variants: priority first, then tie-break, then text.
int _compareVariants(MergeVariant a, MergeVariant b) {
  final byPriority = a.priority.compareTo(b.priority);
  if (byPriority != 0) return byPriority;
  final byTiebreak = a.tiebreak.compareTo(b.tiebreak);
  if (byTiebreak != 0) return byTiebreak;
  return a.text.compareTo(b.text);
}

/// A group of edits from several variants that overlap each other.
final class _Cluster {
  _Cluster(this.entries);

  /// The edits of the cluster, tagged with the index of their variant.
  final List<_TaggedEdit> entries;

  /// Start of the base range covered by the cluster.
  int get start => entries.map((entry) => entry.edit.start).reduce(math.min);

  /// End of the base range covered by the cluster.
  int get end => entries.map((entry) => entry.edit.end).reduce(math.max);

  /// Variant indexes present in this cluster.
  Set<int> get variantIndexes => entries.map((entry) => entry.variant).toSet();
}

/// An edit tagged with the index of the variant it belongs to.
final class _TaggedEdit {
  const _TaggedEdit(this.edit, this.variant);

  /// The edit itself.
  final TextEdit edit;

  /// Index of the variant in the list given to [mergeVariants].
  final int variant;
}

/// Groups the edits of every variant into clusters of overlapping edits.
///
/// Two edits belong to the same cluster when they overlap, whatever the
/// variant they come from. The grouping is computed with a union-find so the
/// result never depends on the order of the edits.
List<_Cluster> _clusterEdits(List<List<TextEdit>> edits) {
  final tagged = <_TaggedEdit>[];
  for (var variant = 0; variant < edits.length; variant++) {
    for (final edit in edits[variant]) {
      tagged.add(_TaggedEdit(edit, variant));
    }
  }
  tagged.sort((a, b) {
    final byStart = a.edit.start.compareTo(b.edit.start);
    if (byStart != 0) return byStart;
    final byVariant = a.variant.compareTo(b.variant);
    if (byVariant != 0) return byVariant;
    return a.edit.end.compareTo(b.edit.end);
  });

  final parent = List<int>.generate(tagged.length, (index) => index);
  int find(int index) {
    var root = index;
    while (parent[root] != root) {
      root = parent[root];
    }
    var current = index;
    while (parent[current] != root) {
      final next = parent[current];
      parent[current] = root;
      current = next;
    }
    return root;
  }

  void union(int first, int second) {
    final rootFirst = find(first);
    final rootSecond = find(second);
    if (rootFirst != rootSecond) parent[rootSecond] = rootFirst;
  }

  for (var i = 0; i < tagged.length; i++) {
    for (var j = i + 1; j < tagged.length; j++) {
      if (tagged[i].variant == tagged[j].variant) continue;
      if (_editsConflict(tagged[i].edit, tagged[j].edit)) union(i, j);
    }
  }

  final groups = <int, List<_TaggedEdit>>{};
  for (var i = 0; i < tagged.length; i++) {
    groups.putIfAbsent(find(i), () => <_TaggedEdit>[]).add(tagged[i]);
  }
  final clusters = groups.values.map(_Cluster.new).toList()
    ..sort((a, b) {
      final byStart = a.start.compareTo(b.start);
      if (byStart != 0) return byStart;
      return a.end.compareTo(b.end);
    });
  return clusters;
}

/// Whether two edits of different variants overlap.
///
/// An insertion is modelled as covering the single base position it happens
/// at, so that two insertions at the same place conflict while an insertion
/// next to a replaced range does not.
bool _editsConflict(TextEdit a, TextEdit b) {
  if (a.isInsertion && b.isInsertion) return a.start == b.start;
  if (a.isInsertion) return a.start >= b.start && a.start < b.end;
  if (b.isInsertion) return b.start >= a.start && b.start < a.end;
  return a.start < b.end && b.start < a.end;
}

/// Builds the merged text of a cluster.
///
/// When only one variant contributes to the cluster the other variants are
/// untouched and their text is kept as is. When several variants contribute,
/// their versions of the region are combined with the longest common prefix
/// and suffix rule, in the deterministic order given by the variant
/// priorities.
String _resolveCluster(
  String base,
  _Cluster cluster,
  List<MergeVariant> variants,
) {
  final involved = cluster.variantIndexes;
  final alternatives = <MergeVariant>[];
  for (final index in involved) {
    final variant = variants[index];
    final region = _variantRegion(base, variant.text, cluster, index);
    alternatives.add(
      MergeVariant(
        text: region,
        priority: variant.priority,
        tiebreak: variant.tiebreak,
      ),
    );
  }
  if (alternatives.length == 1) return alternatives.first.text;
  return _combineAlternatives(alternatives);
}

/// Computes the text produced by [variantText] for the base range of
/// [cluster], given the edits of the variant [variantIndex].
String _variantRegion(
  String base,
  String variantText,
  _Cluster cluster,
  int variantIndex,
) {
  final own =
      cluster.entries.where((entry) => entry.variant == variantIndex).toList()
        ..sort((a, b) => a.edit.start.compareTo(b.edit.start));
  final buffer = StringBuffer();
  var position = cluster.start;
  for (final entry in own) {
    final edit = entry.edit;
    if (edit.start > position) {
      buffer.write(base.substring(position, edit.start));
    }
    buffer.write(edit.replacement);
    position = math.max(position, edit.end);
  }
  if (position < cluster.end) {
    buffer.write(base.substring(position, cluster.end));
  }
  return buffer.toString();
}

/// Combines the alternative versions of a conflicting region.
///
/// The alternatives are ordered by priority, then by tie-break, then by text:
/// the result never depends on the order in which the variants were
/// supplied. The common prefix and the common suffix of all the alternatives
/// are kept once, the diverging middles are concatenated.
String _combineAlternatives(List<MergeVariant> alternatives) {
  final ordered = [...alternatives]..sort(_compareVariants);
  var prefix = 0;
  final shortest = ordered
      .map((variant) => variant.text.length)
      .reduce(math.min);
  while (prefix < shortest &&
      ordered.every(
        (variant) =>
            variant.text.codeUnitAt(prefix) ==
            ordered.first.text.codeUnitAt(prefix),
      )) {
    prefix++;
  }
  var suffix = 0;
  while (suffix < shortest - prefix &&
      ordered.every(
        (variant) =>
            variant.text.codeUnitAt(variant.text.length - 1 - suffix) ==
            ordered.first.text.codeUnitAt(
              ordered.first.text.length - 1 - suffix,
            ),
      )) {
    suffix++;
  }
  final buffer = StringBuffer();
  if (prefix > 0) buffer.write(ordered.first.text.substring(0, prefix));
  for (final variant in ordered) {
    final middle = variant.text.substring(prefix, variant.text.length - suffix);
    buffer.write(middle);
  }
  if (suffix > 0) {
    buffer.write(
      ordered.first.text.substring(ordered.first.text.length - suffix),
    );
  }
  return buffer.toString();
}
