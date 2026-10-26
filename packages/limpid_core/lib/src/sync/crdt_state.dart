import 'package:limpid_core/src/domain/content.dart';
import 'package:limpid_core/src/domain/enums.dart';
import 'package:limpid_core/src/domain/ids.dart';
import 'package:limpid_core/src/domain/mark.dart';
import 'package:limpid_core/src/errors.dart';
import 'package:limpid_core/src/sync/block_state.dart';
import 'package:limpid_core/src/sync/crdt_document.dart';
import 'package:limpid_core/src/sync/ops.dart';
import 'package:limpid_core/src/sync/order_key.dart';

/// The compacted state of a CRDT document.
///
/// The state holds everything the CRDT needs to rebuild a document **without
/// replaying its operations**: the state of every block — with the forest of
/// its versions, its tombstone and its marks — the metadata, and the memory
/// of the operations already applied.
///
/// It is the payload of the compacted snapshot of `limpid_sync`: the journal
/// of the operations is replaced by this state, and the document is restored
/// from it. The state is immutable, like the document it describes.
final class CrdtState {
  /// Creates a state.
  const CrdtState({
    required this.documentId,
    required this.blocks,
    required this.meta,
    required this.appliedKeys,
  });

  /// Captures the state of [document].
  ///
  /// The capture is lossless: the state it returns rebuilds a document that
  /// holds exactly the same blocks, the same metadata and the same memory of
  /// the operations already applied.
  factory CrdtState.fromDocument(CrdtDocument document) => CrdtState(
    documentId: document.id,
    blocks: Map<BlockId, BlockState>.unmodifiable(document.blockStates),
    meta: Map<String, MetaEntry>.unmodifiable(document.metaEntries),
    appliedKeys: Set<String>.unmodifiable(document.appliedKeys),
  );

  /// Creates the empty state of [documentId].
  factory CrdtState.empty(DocumentId documentId) => CrdtState(
    documentId: documentId,
    blocks: const <BlockId, BlockState>{},
    meta: const <String, MetaEntry>{},
    appliedKeys: const <String>{},
  );

  /// The document the state belongs to.
  final DocumentId documentId;

  /// The states of the blocks, keyed by their identifier.
  final Map<BlockId, BlockState> blocks;

  /// The metadata entries, keyed by their name.
  final Map<String, MetaEntry> meta;

  /// The keys of the operations already applied to the document.
  final Set<String> appliedKeys;

  /// Rebuilds the document this state describes.
  CrdtDocument toDocument() => CrdtDocument.fromStates(
    id: documentId,
    blocks: blocks,
    meta: meta,
    applied: appliedKeys,
  );

  /// Encodes the state as JSON.
  ///
  /// The memory of the applied operations is written without the identifier
  /// of the document: the keys are relative to it, and the document is known
  /// when the state is decoded. The encoding therefore stays short even when
  /// the journal it replaces held thousands of operations.
  Map<String, Object?> toJson() => <String, Object?>{
    'doc_id': documentId.value,
    'blocks': <String, Object?>{
      for (final MapEntry<BlockId, BlockState> entry in blocks.entries)
        entry.key.value: _encodeBlock(entry.value),
    },
    'meta': <String, Object?>{
      for (final MapEntry<String, MetaEntry> entry in meta.entries)
        entry.key: _encodeMeta(entry.value),
    },
    'applied': appliedKeys.map(_relativeKey).toList(growable: false)..sort(),
  };

  /// Decodes a state from its JSON representation.
  ///
  /// The state carries the identifier of its document: the memory of the
  /// applied operations is relative to it. The identifier given in [documentId]
  /// is only the fallback, used when the payload does not name the document.
  ///
  /// Throws an [InvalidDocumentException] when the payload is malformed.
  static CrdtState fromJson(
    Map<String, Object?> json, {
    required DocumentId documentId,
  }) {
    final String? rawDocumentId = _text(json, 'doc_id');
    final DocumentId id = rawDocumentId == null
        ? documentId
        : DocumentId(rawDocumentId);
    final Object? rawBlocks = json['blocks'];
    final Object? rawMeta = json['meta'];
    final Object? rawApplied = json['applied'];
    final Map<BlockId, BlockState> blocks = <BlockId, BlockState>{};
    if (rawBlocks is Map<Object?, Object?>) {
      for (final MapEntry<Object?, Object?> entry in rawBlocks.entries) {
        final Object? id = entry.key;
        final Object? value = entry.value;
        if (id is! String || value is! Map<String, Object?>) {
          throw const InvalidDocumentException(
            'A compacted state holds malformed blocks.',
          );
        }
        blocks[BlockId(id)] = _decodeBlock(id, value);
      }
    } else if (rawBlocks != null) {
      throw const InvalidDocumentException(
        'A compacted state holds malformed blocks.',
      );
    }
    final Map<String, MetaEntry> meta = <String, MetaEntry>{};
    if (rawMeta is Map<Object?, Object?>) {
      for (final MapEntry<Object?, Object?> entry in rawMeta.entries) {
        final Object? key = entry.key;
        final Object? value = entry.value;
        if (key is! String || value is! Map<String, Object?>) {
          throw const InvalidDocumentException(
            'A compacted state holds malformed metadata.',
          );
        }
        meta[key] = _decodeMeta(value);
      }
    } else if (rawMeta != null) {
      throw const InvalidDocumentException(
        'A compacted state holds malformed metadata.',
      );
    }
    final Set<String> applied = <String>{};
    if (rawApplied is List<Object?>) {
      final String prefix = '${id.value}/';
      for (final Object? key in rawApplied) {
        if (key is! String) {
          throw const InvalidDocumentException(
            'A compacted state holds malformed operation keys.',
          );
        }
        applied.add(key.startsWith(prefix) ? key : '$prefix$key');
      }
    } else if (rawApplied != null) {
      throw const InvalidDocumentException(
        'A compacted state holds malformed operation keys.',
      );
    }
    return CrdtState(
      documentId: id,
      blocks: Map<BlockId, BlockState>.unmodifiable(blocks),
      meta: Map<String, MetaEntry>.unmodifiable(meta),
      appliedKeys: Set<String>.unmodifiable(applied),
    );
  }

  /// The key of an applied operation, relative to the document.
  String _relativeKey(String key) {
    final String prefix = '${documentId.value}/';
    return key.startsWith(prefix) ? key.substring(prefix.length) : key;
  }

  /// Encodes the state of a block.
  static Map<String, Object?> _encodeBlock(BlockState state) =>
      <String, Object?>{
        'insert': state.insert == null ? null : _encodeInsert(state.insert!),
        'versions': state.versions.map(_encodeVersion).toList(growable: false),
        'deleted_at': state.deletedAt,
        'deleted_by': state.deletedBy?.value,
        'move': state.move == null ? null : _encodeMove(state.move!),
        'marks': <String, Object?>{
          for (final MapEntry<MarkId, MarkState> entry in state.marks.entries)
            entry.key.value: _encodeMark(entry.value),
        },
        'removals': <String, Object?>{
          for (final MapEntry<MarkId, int> entry in state.removals.entries)
            entry.key.value: entry.value,
        },
        'op_count': state.opCount,
      };

  /// Decodes the state of a block.
  static BlockState _decodeBlock(String id, Map<String, Object?> json) {
    final Object? rawVersions = json['versions'];
    final List<ContentVersion> versions = <ContentVersion>[];
    if (rawVersions is List<Object?>) {
      for (final Object? version in rawVersions) {
        if (version is! Map<String, Object?>) {
          throw const InvalidDocumentException(
            'A compacted state holds malformed versions.',
          );
        }
        versions.add(_decodeVersion(version));
      }
    } else if (rawVersions != null) {
      throw const InvalidDocumentException(
        'A compacted state holds malformed versions.',
      );
    }
    final Object? rawInsert = json['insert'];
    final Object? rawMove = json['move'];
    final Object? rawMarks = json['marks'];
    final Object? rawRemovals = json['removals'];
    final Map<MarkId, MarkState> marks = <MarkId, MarkState>{};
    if (rawMarks is Map<Object?, Object?>) {
      for (final MapEntry<Object?, Object?> entry in rawMarks.entries) {
        final Object? id = entry.key;
        final Object? value = entry.value;
        if (id is! String || value is! Map<String, Object?>) {
          throw const InvalidDocumentException(
            'A compacted state holds malformed marks.',
          );
        }
        marks[MarkId(id)] = _decodeMark(value);
      }
    } else if (rawMarks != null) {
      throw const InvalidDocumentException(
        'A compacted state holds malformed marks.',
      );
    }
    final Map<MarkId, int> removals = <MarkId, int>{};
    if (rawRemovals is Map<Object?, Object?>) {
      for (final MapEntry<Object?, Object?> entry in rawRemovals.entries) {
        final Object? id = entry.key;
        final Object? value = entry.value;
        if (id is! String || value is! int) {
          throw const InvalidDocumentException(
            'A compacted state holds malformed mark removals.',
          );
        }
        removals[MarkId(id)] = value;
      }
    } else if (rawRemovals != null) {
      throw const InvalidDocumentException(
        'A compacted state holds malformed mark removals.',
      );
    }
    return BlockState(
      id: BlockId(id),
      insert: rawInsert is Map<String, Object?>
          ? _decodeInsert(rawInsert)
          : null,
      versions: List<ContentVersion>.unmodifiable(versions),
      deletedAt: _integer(json, 'deleted_at'),
      deletedBy: _author(json, 'deleted_by'),
      move: rawMove is Map<String, Object?> ? _decodeMove(rawMove) : null,
      marks: Map<MarkId, MarkState>.unmodifiable(marks),
      removals: Map<MarkId, int>.unmodifiable(removals),
      opCount: _integer(json, 'op_count') ?? 0,
    );
  }

  /// Encodes the insertion of a block.
  static Map<String, Object?> _encodeInsert(InsertInfo insert) =>
      <String, Object?>{
        'lamport': insert.lamport,
        'author': insert.author.value,
        'parent': insert.parent?.value,
        'order': insert.order.value,
        'type': insert.type.name,
        'content': _encodeContent(insert.content),
      };

  /// Decodes the insertion of a block.
  static InsertInfo _decodeInsert(Map<String, Object?> json) => InsertInfo(
    lamport: _integer(json, 'lamport') ?? 0,
    author: _author(json, 'author') ?? const AuthorId(''),
    parent: _blockId(json, 'parent'),
    order: OrderKey(_text(json, 'order') ?? '0'),
    type: _blockType(json, 'type'),
    content: _decodeContent(_map(json, 'content')),
  );

  /// Encodes a version of the content of a block.
  static Map<String, Object?> _encodeVersion(ContentVersion version) =>
      <String, Object?>{
        'lamport': version.lamport,
        'author': version.author.value,
        'content': _encodeContent(version.content),
        'base': version.base == null
            ? null
            : <String, Object?>{
                'lamport': version.base!.lamport,
                'author': version.base!.author.value,
              },
      };

  /// Decodes a version of the content of a block.
  static ContentVersion _decodeVersion(Map<String, Object?> json) {
    final Object? rawBase = json['base'];
    return ContentVersion(
      lamport: _integer(json, 'lamport') ?? 0,
      author: _author(json, 'author') ?? const AuthorId(''),
      content: _decodeContent(_map(json, 'content')),
      base: rawBase is Map<String, Object?>
          ? VersionRef(
              lamport: _integer(rawBase, 'lamport') ?? 0,
              author: _author(rawBase, 'author') ?? const AuthorId(''),
            )
          : null,
    );
  }

  /// Encodes the latest move of a block.
  static Map<String, Object?> _encodeMove(MoveInfo move) => <String, Object?>{
    'lamport': move.lamport,
    'author': move.author.value,
    'parent': move.parent?.value,
    'order': move.order.value,
  };

  /// Decodes the latest move of a block.
  static MoveInfo _decodeMove(Map<String, Object?> json) => MoveInfo(
    lamport: _integer(json, 'lamport') ?? 0,
    author: _author(json, 'author') ?? const AuthorId(''),
    parent: _blockId(json, 'parent'),
    order: OrderKey(_text(json, 'order') ?? '0'),
  );

  /// Encodes a mark of a block.
  static Map<String, Object?> _encodeMark(MarkState mark) => <String, Object?>{
    'added_at': mark.addedAt,
    'added_by': mark.addedBy.value,
    'type': mark.type.name,
    'range': <String, Object?>{
      'start': mark.range.start,
      'end': mark.range.end,
    },
    'body': mark.body,
  };

  /// Decodes a mark of a block.
  static MarkState _decodeMark(Map<String, Object?> json) => MarkState(
    addedAt: _integer(json, 'added_at') ?? 0,
    addedBy: _author(json, 'added_by') ?? const AuthorId(''),
    type: _markType(json, 'type'),
    range: MarkRange(
      start: _integer(_map(json, 'range'), 'start') ?? 0,
      end: _integer(_map(json, 'range'), 'end') ?? 0,
    ),
    body: _text(json, 'body') ?? '',
  );

  /// Encodes a metadata entry.
  static Map<String, Object?> _encodeMeta(MetaEntry entry) => <String, Object?>{
    'lamport': entry.lamport,
    'author': entry.author.value,
    'value': entry.value,
  };

  /// Decodes a metadata entry.
  static MetaEntry _decodeMeta(Map<String, Object?> json) => MetaEntry(
    lamport: _integer(json, 'lamport') ?? 0,
    author: _author(json, 'author') ?? const AuthorId(''),
    value: _text(json, 'value') ?? '',
  );

  /// Encodes the content of a block.
  static Map<String, Object?> _encodeContent(BlockContent content) =>
      switch (content) {
        TextContent() => <String, Object?>{
          'kind': 'text',
          'text': content.text,
        },
        InlineContent() => <String, Object?>{
          'kind': 'inline',
          'delta_json': content.deltaJson,
          'plain_text': content.plainText,
        },
      };

  /// Decodes the content of a block.
  static BlockContent _decodeContent(Map<String, Object?> json) {
    final String kind = _text(json, 'kind') ?? 'text';
    return switch (kind) {
      'text' => TextContent(_text(json, 'text') ?? ''),
      'inline' => InlineContent(
        deltaJson: _text(json, 'delta_json') ?? '',
        plainText: _text(json, 'plain_text') ?? '',
      ),
      _ => throw InvalidDocumentException(
        'A compacted state holds an unknown content kind "$kind".',
      ),
    };
  }

  /// Reads a field of text, `null` when it is missing.
  static String? _text(Map<String, Object?> json, String key) {
    final Object? value = json[key];
    if (value == null) return null;
    if (value is String) return value;
    throw InvalidDocumentException(
      'The field "$key" of a compacted state is not a text.',
    );
  }

  /// Reads a field of integers, `null` when it is missing.
  static int? _integer(Map<String, Object?> json, String key) {
    final Object? value = json[key];
    if (value == null) return null;
    if (value is int) return value;
    throw InvalidDocumentException(
      'The field "$key" of a compacted state is not an integer.',
    );
  }

  /// Reads a field of authors, `null` when it is missing.
  static AuthorId? _author(Map<String, Object?> json, String key) {
    final String? value = _text(json, key);
    return value == null ? null : AuthorId(value);
  }

  /// Reads a field of block identifiers, `null` when it is missing.
  static BlockId? _blockId(Map<String, Object?> json, String key) {
    final String? value = _text(json, key);
    return value == null ? null : BlockId(value);
  }

  /// Reads a field of objects, an empty object when it is missing.
  static Map<String, Object?> _map(Map<String, Object?> json, String key) {
    final Object? value = json[key];
    if (value == null) return const <String, Object?>{};
    if (value is Map<String, Object?>) return value;
    throw InvalidDocumentException(
      'The field "$key" of a compacted state is not an object.',
    );
  }

  /// Reads a field of block types.
  static BlockType _blockType(Map<String, Object?> json, String key) {
    final String name = _text(json, key) ?? BlockType.paragraph.name;
    for (final BlockType type in BlockType.values) {
      if (type.name == name) return type;
    }
    throw InvalidDocumentException(
      'A compacted state holds an unknown block type "$name".',
    );
  }

  /// Reads a field of mark types.
  static MarkType _markType(Map<String, Object?> json, String key) {
    final String name = _text(json, key) ?? MarkType.comment.name;
    for (final MarkType type in MarkType.values) {
      if (type.name == name) return type;
    }
    throw InvalidDocumentException(
      'A compacted state holds an unknown mark type "$name".',
    );
  }
}
