import 'package:limpid_core/limpid_core.dart';

/// The nature of a divergence detected between two versions of a block.
enum ConflictKind {
  /// Two concurrent versions of the text of a block diverged.
  content,

  /// Two concurrent moves of the same block diverged.
  structure,

  /// Two concurrent writes of the same scalar metadata diverged.
  meta,
}

/// One of the two versions presented to the author when a conflict is
/// detected.
///
/// A version carries everything the UI needs to display it next to its
/// counterpart: the text, its author, its Lamport timestamp and the version
/// it derives from (the common ancestor used by the 3-way merge).
final class ConflictVersion {
  /// Creates a conflict version.
  const ConflictVersion({
    required this.content,
    required this.author,
    required this.lamport,
    this.baseVersion,
    this.baseContent,
  });

  /// The content of the version.
  final BlockContent content;

  /// The author who wrote the version.
  final AuthorId author;

  /// The Lamport timestamp of the operation that produced the version.
  final int lamport;

  /// The version this one derives from, `null` when it was written from
  /// scratch.
  final VersionRef? baseVersion;

  /// The content of [baseVersion], `null` when the ancestor is unknown.
  final BlockContent? baseContent;

  /// The plain text projection of the content.
  String get plainText => content.plainText;

  @override
  String toString() => 'ConflictVersion($author, $lamport)';
}

/// The position of a conflicting block inside the document.
///
/// The position is expressed both as a flat index (the position in the depth
/// first traversal of the tree) and as a fractional order key, so the UI can
/// display "Chapter II · Scene 2 · paragraph 3" without recomputing
/// anything.
final class ConflictPosition {
  /// Creates a conflict position.
  const ConflictPosition({
    required this.blockId,
    required this.index,
    required this.order,
    required this.parent,
  });

  /// The block the conflict is about.
  final BlockId blockId;

  /// The index of the block in the flat, depth first list of the document.
  final int index;

  /// The fractional index of the block among its siblings.
  final OrderKey order;

  /// The parent of the block, `null` for a root block.
  final BlockId? parent;

  @override
  String toString() => 'ConflictPosition($blockId, #$index)';
}

/// A divergence detected between the local version and the remote version of
/// the same block.
///
/// The report never decides: it carries both versions so the author can keep
/// one of them or merge them, exactly like the "Hors-ligne & synchronisation"
/// screen of the product.
final class ConflictReport {
  /// Creates a conflict report.
  const ConflictReport({
    required this.documentId,
    required this.blockId,
    required this.kind,
    required this.local,
    required this.remote,
    required this.position,
    required this.detectedAt,
  });

  /// The document the conflict belongs to.
  final DocumentId documentId;

  /// The block whose versions diverged.
  final BlockId blockId;

  /// The nature of the divergence.
  final ConflictKind kind;

  /// The local version of the block.
  final ConflictVersion local;

  /// The remote version of the block.
  final ConflictVersion remote;

  /// The position of the block in the document.
  final ConflictPosition position;

  /// The moment the divergence was detected.
  final DateTime detectedAt;

  /// The content obtained by merging both versions with the 3-way merge of
  /// `limpid_core`.
  ///
  /// The merge is deterministic: it only depends on the two versions and on
  /// their common ancestor.
  BlockContent get mergedContent {
    final base = local.baseContent ?? remote.baseContent;
    final baseText = base?.plainText ?? '';
    final merged = mergeThreeWay(
      base: baseText,
      left: local.plainText,
      right: remote.plainText,
    );
    return (base ?? const TextContent('')).withPlainText(merged);
  }

  @override
  String toString() =>
      'ConflictReport($blockId, $kind, local=$local, remote=$remote)';
}

/// The choice offered to the author when a conflict is reported.
enum ConflictResolution {
  /// Keep the local version and discard the remote one.
  keepLocal,

  /// Keep the remote version and discard the local one.
  keepRemote,

  /// Keep both, merged into a single version.
  merge,
}

/// Applies a [ConflictResolution] to a [ConflictReport].
final class ConflictResolver {
  /// Creates a resolver.
  const ConflictResolver();

  /// Returns the content that keeps the resolution chosen by the author.
  BlockContent resolve(ConflictReport report, ConflictResolution resolution) {
    return switch (resolution) {
      ConflictResolution.keepLocal => report.local.content,
      ConflictResolution.keepRemote => report.remote.content,
      ConflictResolution.merge => report.mergedContent,
    };
  }
}
