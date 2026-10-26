import 'package:limpid_core/src/domain/block.dart';
import 'package:limpid_core/src/domain/content.dart';
import 'package:limpid_core/src/domain/ids.dart';
import 'package:limpid_core/src/domain/mark.dart';
import 'package:limpid_core/src/sync/block_state.dart';
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
  final marks = <MarkId, MarkRange>{};
  for (final mark in state.marks.keys) {
    if (state.isMarkPresent(mark)) {
      marks[mark] = state.marks[mark]!.range;
    }
  }
  final lamport = latestLamport(state);
  return Block(
    id: state.id,
    doc: docId,
    parent: parent,
    order: order,
    type: insert.type,
    content: effectiveContent(state),
    marks: Map<MarkId, MarkRange>.unmodifiable(marks),
    lamport: lamport,
    author: latestAuthor(state, lamport),
    deleted: state.isDeleted,
    version: state.opCount,
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
  final versions = state.versions;
  if (versions.isEmpty) {
    return state.insert?.content ?? const TextContent('');
  }
  final leaves = _leaves(versions);
  if (leaves.length == 1) return leaves.first.content;
  final base = _mergeBase(state, leaves);
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
BlockContent _mergeBase(BlockState state, List<ContentVersion> leaves) {
  final byKey = <String, ContentVersion>{
    for (final version in state.versions) version.ref.key: version,
  };
  List<ContentVersion>? common;
  for (final leaf in leaves) {
    final chain = _chain(leaf, byKey);
    common = common == null ? chain : _commonPrefix(common, chain);
    if (common.isEmpty) break;
  }
  final ancestor = (common == null || common.isEmpty) ? null : common.first;
  return ancestor?.content ?? state.insert?.content ?? const TextContent('');
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
