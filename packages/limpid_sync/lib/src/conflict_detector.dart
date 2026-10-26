import 'package:limpid_core/limpid_core.dart';
import 'package:limpid_sync/src/conflict.dart';

/// A content version observed in the operation log.
final class _ContentCandidate {
  const _ContentCandidate({
    required this.blockId,
    required this.content,
    required this.author,
    required this.lamport,
    this.base,
  });

  final BlockId blockId;
  final BlockContent content;
  final AuthorId author;
  final int lamport;
  final VersionRef? base;

  /// The identity of the version, comparable with [VersionRef.key].
  String get key => '$lamport/${author.value}';
}

/// Detects the divergences between the local and the remote versions of a
/// block.
///
/// The detector never decides: it reports the two versions and their position
/// so the author can arbitrate. It only reports a divergence when the two
/// versions are genuinely *concurrent* — when one derives from the other,
/// the later version simply supersedes the earlier one and there is nothing
/// to arbitrate.
final class ConflictDetector {
  /// Creates a detector.
  const ConflictDetector();

  /// Detects the conflicts between [localOperations] and [remoteOperations].
  ///
  /// [document] is only used to locate the conflicting blocks; it is never
  /// modified.
  List<ConflictReport> detect({
    required CrdtDocument document,
    required List<SyncOp> localOperations,
    required List<SyncOp> remoteOperations,
    DateTime? detectedAt,
  }) {
    final when = detectedAt ?? DateTime.now();
    final contents = _collectContents(<SyncOp>[
      ...localOperations,
      ...remoteOperations,
    ]);
    final local = _latestByBlock(localOperations);
    final remote = _latestByBlock(remoteOperations);
    final reports = <ConflictReport>[];

    for (final entry in local.entries) {
      final other = remote[entry.key];
      if (other == null) continue;
      final report = _compare(
        document: document,
        local: entry.value,
        remote: other,
        contents: contents,
        detectedAt: when,
      );
      if (report != null) reports.add(report);
    }
    return List<ConflictReport>.unmodifiable(reports);
  }

  ConflictReport? _compare({
    required CrdtDocument document,
    required _ContentCandidate local,
    required _ContentCandidate remote,
    required Map<String, BlockContent> contents,
    required DateTime detectedAt,
  }) {
    if (local.content.plainText == remote.content.plainText) return null;
    if (local.author == remote.author) return null;
    if (!_isConcurrent(local, remote)) return null;

    final baseContent = _baseContent(local, remote, contents);
    return ConflictReport(
      documentId: document.id,
      blockId: local.blockId,
      kind: ConflictKind.content,
      local: ConflictVersion(
        content: local.content,
        author: local.author,
        lamport: local.lamport,
        baseVersion: local.base,
        baseContent: baseContent,
      ),
      remote: ConflictVersion(
        content: remote.content,
        author: remote.author,
        lamport: remote.lamport,
        baseVersion: remote.base,
        baseContent: baseContent,
      ),
      position: _position(document, local.blockId),
      detectedAt: detectedAt,
    );
  }

  /// Whether neither version derives from the other.
  bool _isConcurrent(_ContentCandidate local, _ContentCandidate remote) {
    if (local.base?.key == remote.key) return false;
    if (remote.base?.key == local.key) return false;
    return true;
  }

  /// The content of the common ancestor of the two versions.
  BlockContent? _baseContent(
    _ContentCandidate local,
    _ContentCandidate remote,
    Map<String, BlockContent> contents,
  ) {
    final candidates = <String?>[local.base?.key, remote.base?.key];
    for (final key in candidates) {
      if (key == null) continue;
      final content = contents[key];
      if (content != null) return content;
    }
    return null;
  }

  /// The content of every version seen in [operations], keyed by version key.
  Map<String, BlockContent> _collectContents(List<SyncOp> operations) {
    final contents = <String, BlockContent>{};
    for (final op in operations) {
      switch (op) {
        case InsertBlockOp():
          contents['${op.lamport}/${op.author.value}'] = op.content;
        case UpdateContentOp():
          contents['${op.lamport}/${op.author.value}'] = op.content;
        case DeleteBlockOp():
        case MoveBlockOp():
        case SetMetaOp():
        case AddMarkOp():
        case RemoveMarkOp():
          break;
      }
    }
    return contents;
  }

  /// The most recent content version of each block.
  Map<BlockId, _ContentCandidate> _latestByBlock(List<SyncOp> operations) {
    final latest = <BlockId, _ContentCandidate>{};
    for (final op in operations) {
      final candidate = switch (op) {
        InsertBlockOp() => _ContentCandidate(
          blockId: op.blockId,
          content: op.content,
          author: op.author,
          lamport: op.lamport,
        ),
        UpdateContentOp() => _ContentCandidate(
          blockId: op.blockId,
          content: op.content,
          author: op.author,
          lamport: op.lamport,
          base: op.base?.version,
        ),
        _ => null,
      };
      if (candidate == null) continue;
      final current = latest[candidate.blockId];
      if (current == null || _isNewer(candidate, current)) {
        latest[candidate.blockId] = candidate;
      }
    }
    return latest;
  }

  /// Whether [candidate] supersedes [current].
  ///
  /// The rule is the one of the CRDT: the Lamport timestamp comes first and
  /// the author identifier breaks the ties.
  bool _isNewer(_ContentCandidate candidate, _ContentCandidate current) {
    if (candidate.lamport != current.lamport) {
      return candidate.lamport > current.lamport;
    }
    return candidate.author.value.compareTo(current.author.value) > 0;
  }

  /// The position of [blockId] inside [document].
  ConflictPosition _position(CrdtDocument document, BlockId blockId) {
    final blocks = document.blocks;
    final index = blocks.indexWhere((block) => block.id == blockId);
    if (index < 0) {
      return ConflictPosition(
        blockId: blockId,
        index: -1,
        order: OrderKey.initial,
        parent: null,
      );
    }
    final block = blocks[index];
    return ConflictPosition(
      blockId: blockId,
      index: index,
      order: block.order,
      parent: block.parent,
    );
  }
}
