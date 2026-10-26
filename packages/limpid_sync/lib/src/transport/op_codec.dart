import 'package:limpid_core/limpid_core.dart';
import 'package:limpid_sync/src/errors.dart';

/// The version of the wire protocol implemented by this codec.
///
/// The value is the one documented in `docs/ARCHITECTURE.md` §5.7.
const int syncProtocolSchemaVersion = 1;

/// Encodes and decodes the CRDT operations exchanged with the API.
///
/// The wire format is the one of `docs/ARCHITECTURE.md` §5.1 and §5.2:
/// snake_case JSON, a `type` discriminator and a typed `payload`.
///
/// ## About `op_id`
///
/// The protocol reserves a ULID for `op_id`. `limpid_core` does not assign
/// one to its operations — their identity is `(doc_id, lamport,
/// author_id)` — so the codec writes the deterministic operation key
/// instead. It is unique and stable, which is exactly what the server side
/// deduplication needs, and it keeps the encoding reproducible.
final class OpCodec {
  const OpCodec._();

  /// Encodes [op] into its wire representation.
  static Map<String, Object?> encode(SyncOp op) => <String, Object?>{
    'op_id': op.operationKey,
    'doc_id': op.doc.value,
    'lamport': op.lamport,
    'author_id': op.author.value,
    'type': op.kind,
    'payload': encodePayload(op),
    'schema_version': syncProtocolSchemaVersion,
  };

  /// Encodes [op] into the payload of its wire representation.
  static Map<String, Object?> encodePayload(SyncOp op) {
    return switch (op) {
      InsertBlockOp() => <String, Object?>{
        'block_id': op.blockId.value,
        'parent_id': op.parent?.value,
        'order_key': op.order.value,
        'type': op.type.name,
        'content': encodeContent(op.content),
      },
      DeleteBlockOp() => <String, Object?>{'block_id': op.blockId.value},
      UpdateContentOp() => <String, Object?>{
        'block_id': op.blockId.value,
        'content': encodeContent(op.content),
        'base_version': op.base?.version.lamport,
        'base_author': op.base?.version.author.value,
      },
      MoveBlockOp() => <String, Object?>{
        'block_id': op.blockId.value,
        'parent_id': op.parent?.value,
        'order_key': op.order.value,
      },
      SetMetaOp() => <String, Object?>{'key': op.key, 'value': op.value},
      AddMarkOp() => <String, Object?>{
        'mark_id': op.markId.value,
        'block_id': op.blockId.value,
        'mark_type': op.type.name,
        'range': <String, Object?>{
          'start': op.range.start,
          'end': op.range.end,
        },
        'body': op.body,
      },
      RemoveMarkOp() => <String, Object?>{
        'mark_id': op.markId.value,
        'block_id': op.blockId.value,
      },
    };
  }

  /// Encodes the content of a block.
  static Map<String, Object?> encodeContent(BlockContent content) {
    return switch (content) {
      TextContent() => <String, Object?>{'kind': 'text', 'text': content.text},
      InlineContent() => <String, Object?>{
        'kind': 'inline',
        'delta_json': content.deltaJson,
        'plain_text': content.plainText,
      },
    };
  }

  /// Decodes an operation from its wire representation.
  ///
  /// Throws a [SyncTransportException] when the payload is malformed.
  static SyncOp decode(Map<String, Object?> json) {
    try {
      final doc = DocumentId(_requiredString(json, 'doc_id'));
      final lamport = _requiredInt(json, 'lamport');
      final author = AuthorId(_requiredString(json, 'author_id'));
      final type = _requiredString(json, 'type');
      final payload = _requiredMap(json, 'payload');
      return switch (type) {
        'insertBlock' => InsertBlockOp(
          doc: doc,
          lamport: lamport,
          author: author,
          blockId: BlockId(_requiredString(payload, 'block_id')),
          parent: _optionalId(payload, 'parent_id'),
          order: OrderKey(_requiredString(payload, 'order_key')),
          type: _enumByName(BlockType.values, _requiredString(payload, 'type')),
          content: _decodeContent(_requiredMap(payload, 'content')),
        ),
        'deleteBlock' => DeleteBlockOp(
          doc: doc,
          lamport: lamport,
          author: author,
          blockId: BlockId(_requiredString(payload, 'block_id')),
        ),
        'updateContent' => UpdateContentOp(
          doc: doc,
          lamport: lamport,
          author: author,
          blockId: BlockId(_requiredString(payload, 'block_id')),
          content: _decodeContent(_requiredMap(payload, 'content')),
          base: _decodeBase(payload),
        ),
        'moveBlock' => MoveBlockOp(
          doc: doc,
          lamport: lamport,
          author: author,
          blockId: BlockId(_requiredString(payload, 'block_id')),
          parent: _optionalId(payload, 'parent_id'),
          order: OrderKey(_requiredString(payload, 'order_key')),
        ),
        'setMeta' => SetMetaOp(
          doc: doc,
          lamport: lamport,
          author: author,
          key: _requiredString(payload, 'key'),
          value: _requiredString(payload, 'value'),
        ),
        'addMark' => AddMarkOp(
          doc: doc,
          lamport: lamport,
          author: author,
          markId: MarkId(_requiredString(payload, 'mark_id')),
          blockId: BlockId(_requiredString(payload, 'block_id')),
          type: _enumByName(
            MarkType.values,
            _requiredString(payload, 'mark_type'),
          ),
          range: _decodeRange(_requiredMap(payload, 'range')),
          body: _optionalString(payload, 'body') ?? '',
        ),
        'removeMark' => RemoveMarkOp(
          doc: doc,
          lamport: lamport,
          author: author,
          markId: MarkId(_requiredString(payload, 'mark_id')),
          blockId: BlockId(_requiredString(payload, 'block_id')),
        ),
        _ => throw SyncTransportException(
          'Unknown operation type "$type".',
          code: 'sync_invalid_payload',
        ),
      };
    } on SyncException {
      rethrow;
    } on InvalidSyncOperationException catch (error) {
      throw SyncTransportException(
        'Malformed operation payload: ${error.message}',
        code: 'sync_invalid_payload',
        cause: error,
      );
    } on ArgumentError catch (error) {
      throw SyncTransportException(
        'Malformed operation payload: ${error.message}',
        code: 'sync_invalid_payload',
        cause: error,
      );
    }
  }

  /// Decodes a list of operations.
  static List<SyncOp> decodeList(List<Object?> json) {
    return List<SyncOp>.unmodifiable(
      json.map((item) {
        if (item is! Map<String, Object?>) {
          throw SyncTransportException(
            'An operation must be a JSON object.',
            code: 'sync_invalid_payload',
          );
        }
        return decode(item);
      }),
    );
  }

  static BlockContent _decodeContent(Map<String, Object?> json) {
    final kind = _requiredString(json, 'kind');
    return switch (kind) {
      'text' => TextContent(_requiredString(json, 'text')),
      'inline' => InlineContent(
        deltaJson: _requiredString(json, 'delta_json'),
        plainText: _requiredString(json, 'plain_text'),
      ),
      _ => throw SyncTransportException(
        'Unknown content kind "$kind".',
        code: 'sync_invalid_payload',
      ),
    };
  }

  static ContentBase? _decodeBase(Map<String, Object?> payload) {
    final lamport = payload['base_version'];
    final author = payload['base_author'];
    if (lamport is! int || author is! String) return null;
    return ContentBase(
      version: VersionRef(lamport: lamport, author: AuthorId(author)),
    );
  }

  static MarkRange _decodeRange(Map<String, Object?> json) {
    final start = _requiredInt(json, 'start');
    final end = _requiredInt(json, 'end');
    if (start < 0 || end < start) {
      throw SyncTransportException(
        'Invalid mark range [$start, $end[.',
        code: 'sync_invalid_payload',
      );
    }
    return MarkRange(start: start, end: end);
  }

  static T _enumByName<T extends Enum>(List<T> values, String name) {
    for (final value in values) {
      if (value.name == name) return value;
    }
    throw SyncTransportException(
      'Unknown enum value "$name".',
      code: 'sync_invalid_payload',
    );
  }

  static BlockId? _optionalId(Map<String, Object?> json, String key) {
    final value = _optionalString(json, key);
    return value == null ? null : BlockId(value);
  }

  static String? _optionalString(Map<String, Object?> json, String key) {
    final value = json[key];
    if (value == null) return null;
    if (value is! String) {
      throw SyncTransportException(
        'Field "$key" must be a string.',
        code: 'sync_invalid_payload',
      );
    }
    return value;
  }

  static String _requiredString(Map<String, Object?> json, String key) {
    final value = json[key];
    if (value is! String) {
      throw SyncTransportException(
        'Field "$key" is missing or is not a string.',
        code: 'sync_invalid_payload',
      );
    }
    return value;
  }

  static int _requiredInt(Map<String, Object?> json, String key) {
    final value = json[key];
    if (value is! int) {
      throw SyncTransportException(
        'Field "$key" is missing or is not an integer.',
        code: 'sync_invalid_payload',
      );
    }
    return value;
  }

  static Map<String, Object?> _requiredMap(
    Map<String, Object?> json,
    String key,
  ) {
    final value = json[key];
    if (value is! Map<String, Object?>) {
      throw SyncTransportException(
        'Field "$key" is missing or is not an object.',
        code: 'sync_invalid_payload',
      );
    }
    return value;
  }
}
