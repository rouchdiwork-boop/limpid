import 'package:limpid_core/src/domain/block.dart';
import 'package:limpid_core/src/domain/content.dart';
import 'package:limpid_core/src/domain/ids.dart';
import 'package:limpid_core/src/domain/mark.dart';
import 'package:limpid_core/src/sync/block_state.dart';
import 'package:limpid_core/src/sync/internal/text_diff.dart';
import 'package:limpid_core/src/sync/ops.dart';
import 'package:limpid_core/src/sync/three_way_merge.dart';

/// Builds the effective block of [state], `null` when the block is unknown.
Block? effectiveBlock(BlockState state, DocumentId docId) {
  final insert = state.insert;
  if (insert == null) return null;
  final move = state.move;
  final useMove =
      move != null && isNewerVersion(move.lamport, move.author, insert.key);
  final parent = useMove ? move.parent : insert.parent;
  final order = useMove ? move.order : insert.order;
  final BlockContent content = effectiveContent(state);
  final lamport = latestLamport(state);
  return Block(
    id: state.id,
    doc: docId,
    parent: parent,
    order: order,
    type: insert.type,
    content: content,
    marks: effectiveMarkRanges(state, content),
    lamport: lamport,
    author: latestAuthor(state, lamport),
    deleted: state.isDeleted,
    version: state.opCount,
  );
}

/// The ranges of the marks of a block, moved on the text they cover.
///
/// A mark is a surcharge of the CRDT: it never conflicts with the text. But
/// its range is expressed in the coordinates of the text it was written on,
/// and the text moves when the block is rewritten. The range is therefore
/// computed again on the effective content of the block: it follows the words
/// it covers.
Map<MarkId, MarkRange> effectiveMarkRanges(
  BlockState state,
  BlockContent content,
) {
  final String text = content.plainText;
  final Map<MarkId, MarkRange> ranges = <MarkId, MarkRange>{};
  final Map<String, RangeMapper> mappers = <String, RangeMapper>{};
  for (final MarkId id in state.marks.keys) {
    if (!state.isMarkPresent(id)) continue;
    final MarkState mark = state.marks[id]!;
    final String reference = referenceContentOf(state, mark).plainText;
    final RangeMapper mapper = mappers.putIfAbsent(
      reference,
      () => RangeMapper(reference: reference, text: text),
    );
    ranges[id] = mapper.map(mark.range);
  }
  return Map<MarkId, MarkRange>.unmodifiable(ranges);
}

/// The content the range of [mark] was computed on.
///
/// The mark was added after the versions that carry its text: the reference
/// is the content of those versions. It is the text the author was reading
/// when the mark was written, and the diff between it and the effective
/// content moves the range.
///
/// A version written by another author and received after the mark may join
/// the reference: the CRDT does not keep what the author was reading. The
/// range then follows the words of the text the two versions share.
BlockContent referenceContentOf(BlockState state, MarkState mark) {
  final List<ContentVersion> versions = state.versions
      .where((ContentVersion version) => version.lamport < mark.addedAt)
      .toList(growable: false);
  return effectiveContentOf(
    versions,
    state.insert?.content ?? const TextContent(''),
  );
}

/// The most recent known content version of [state].
VersionRef? latestContentVersionOf(BlockState state) {
  ContentVersion? latest;
  for (final version in state.versions) {
    if (latest == null ||
        version.lamport > latest.lamport ||
        (version.lamport == latest.lamport &&
            version.author.value.compareTo(latest.author.value) > 0)) {
      latest = version;
    }
  }
  return latest?.ref;
}

/// The latest Lamport timestamp carried by the state of a block.
int latestLamport(BlockState state) {
  var latest = state.insert?.lamport ?? 0;
  for (final version in state.versions) {
    if (version.lamport > latest) latest = version.lamport;
  }
  final deletion = state.deletedAt;
  if (deletion != null && deletion > latest) latest = deletion;
  final move = state.move;
  if (move != null && move.lamport > latest) latest = move.lamport;
  return latest;
}

/// The author of the operation that carried [lamport].
AuthorId latestAuthor(BlockState state, int lamport) {
  var author = state.insert?.author ?? const AuthorId('');
  for (final version in state.versions) {
    if (version.lamport == lamport &&
        version.author.value.compareTo(author.value) > 0) {
      author = version.author;
    }
  }
  final deletion = state.deletedBy;
  if (deletion != null && state.deletedAt == lamport) {
    if (deletion.value.compareTo(author.value) > 0) author = deletion;
  }
  final move = state.move;
  if (move != null &&
      move.lamport == lamport &&
      move.author.value.compareTo(author.value) > 0) {
    author = move.author;
  }
  return author;
}

/// Computes the effective content of a block from its version forest.
///
/// When several versions are concurrent, the common ancestor of the leaves is
/// used as the base of the 3-way merge. The result only depends on the set
/// of versions, never on the order in which they were received.
BlockContent effectiveContent(BlockState state) {
  return effectiveContentOf(
    state.versions,
    state.insert?.content ?? const TextContent(''),
  );
}

/// Computes the effective content of a set of versions.
///
/// [fallback] is the content of the block when it holds no version at all.
/// The result only depends on the set of versions, never on the order in
/// which they were received.
BlockContent effectiveContentOf(
  List<ContentVersion> versions,
  BlockContent fallback,
) {
  if (versions.isEmpty) {
    return fallback;
  }
  final leaves = _leaves(versions);
  if (leaves.length == 1) return leaves.first.content;
  final base = _mergeBase(versions, leaves, fallback);
  final variants = leaves
      .map(
        (version) => MergeVariant(
          text: version.content.plainText,
          priority: version.lamport,
          tiebreak: version.author.value,
        ),
      )
      .toList(growable: false);
  final merged = mergeVariants(base: base.plainText, variants: variants);
  return base.withPlainText(merged);
}

/// The versions of [versions] that no other version derives from.
List<ContentVersion> _leaves(List<ContentVersion> versions) {
  final referenced = <String>{};
  for (final version in versions) {
    final base = version.base;
    if (base != null) referenced.add(base.key);
  }
  return versions
      .where((version) => !referenced.contains(version.ref.key))
      .toList(growable: false);
}

/// The common ancestor used as the base of the 3-way merge.
BlockContent _mergeBase(
  List<ContentVersion> versions,
  List<ContentVersion> leaves,
  BlockContent fallback,
) {
  final byKey = <String, ContentVersion>{
    for (final version in versions) version.ref.key: version,
  };
  List<ContentVersion>? common;
  for (final leaf in leaves) {
    final chain = _chain(leaf, byKey);
    common = common == null ? chain : _commonPrefix(common, chain);
    if (common.isEmpty) break;
  }
  final ancestor = (common == null || common.isEmpty) ? null : common.first;
  return ancestor?.content ?? fallback;
}

/// The chain of ancestors of [leaf], from the leaf to the root.
List<ContentVersion> _chain(
  ContentVersion leaf,
  Map<String, ContentVersion> byKey,
) {
  final chain = <ContentVersion>[];
  final seen = <String>{};
  ContentVersion? current = leaf;
  while (current != null && seen.add(current.ref.key)) {
    chain.add(current);
    final base = current.base;
    current = base == null ? null : byKey[base.key];
  }
  return chain;
}

/// The longest common prefix of two chains.
List<ContentVersion> _commonPrefix(
  List<ContentVersion> a,
  List<ContentVersion> b,
) {
  final length = a.length < b.length ? a.length : b.length;
  var index = 0;
  while (index < length && a[index].ref == b[index].ref) {
    index++;
  }
  return a.sublist(0, index);
}

/// Orders the blocks as a depth first traversal of the tree.
List<Block> orderBlocks(List<Block> blocks) {
  final byId = <BlockId, Block>{for (final block in blocks) block.id: block};
  final children = <BlockId?, List<Block>>{};
  for (final block in blocks) {
    final parent = block.parent;
    final bucket = children.putIfAbsent(parent, () => <Block>[]);
    bucket.add(block);
  }
  for (final bucket in children.values) {
    bucket.sort(_compareSiblings);
  }
  final ordered = <Block>[];
  final visited = <BlockId>{};
  final roots = blocks.where((block) {
    final parent = block.parent;
    return parent == null || !byId.containsKey(parent);
  }).toList()..sort(_compareSiblings);
  for (final root in roots) {
    _visit(root, children, visited, ordered);
  }
  final orphans = blocks.where((block) => !visited.contains(block.id)).toList()
    ..sort(_compareSiblings);
  for (final orphan in orphans) {
    _visit(orphan, children, visited, ordered);
  }
  return ordered;
}

void _visit(
  Block block,
  Map<BlockId?, List<Block>> children,
  Set<BlockId> visited,
  List<Block> ordered,
) {
  if (!visited.add(block.id)) return;
  ordered.add(block);
  final bucket = children[block.id];
  if (bucket == null) return;
  for (final child in bucket) {
    _visit(child, children, visited, ordered);
  }
}

/// Orders two sibling blocks by fractional index, then by identifier.
int _compareSiblings(Block a, Block b) {
  final byOrder = a.order.compareTo(b.order);
  if (byOrder != 0) return byOrder;
  return a.id.value.compareTo(b.id.value);
}
