import 'package:limpid_core/limpid_core.dart';

import '../db/sync_op_record.dart';
import '../errors/app_exception.dart';

/// The version of the sync protocol spoken by this server.
const int syncSchemaVersion = 1;

/// The oldest version of the sync protocol the server still accepts.
const int minSupportedSchemaVersion = 1;

/// The names of the operations of the sync protocol.
abstract final class SyncOpTypes {
  /// Inserts a block.
  static const String insertBlock = 'insertBlock';

  /// Deletes a block.
  static const String deleteBlock = 'deleteBlock';

  /// Replaces the content of a block.
  static const String updateContent = 'updateContent';

  /// Moves a block.
  static const String moveBlock = 'moveBlock';

  /// Sets a scalar metadata.
  static const String setMeta = 'setMeta';

  /// Adds a mark.
  static const String addMark = 'addMark';

  /// Removes a mark.
  static const String removeMark = 'removeMark';

  /// Every known operation name.
  static const List<String> all = <String>[
    insertBlock,
    deleteBlock,
    updateContent,
    moveBlock,
    setMeta,
    addMark,
    removeMark,
  ];
}

/// Decodes the operations of the sync protocol.
///
/// The decoder is the boundary of the sync engine: it turns an untyped JSON
/// payload into the typed operations of `limpid_core`, and refuses anything
/// it does not understand instead of letting it reach the CRDT.
abstract final class SyncProtocol {
  /// Decodes one operation.
  static SyncOp decode(Map<String, dynamic> json) {
    _requireString(json, 'op_id');
    final String docId = _requireString(json, 'doc_id');
    final int lamport = _requireInt(json, 'lamport');
    final String authorId = _requireString(json, 'author_id');
    final String type = _requireString(json, 'type');
    final int schemaVersion = json['schema_version'] is int
        ? json['schema_version']! as int
        : syncSchemaVersion;

    if (schemaVersion > syncSchemaVersion) {
      throw ClientAheadException(
        message:
            'Votre application est plus récente que le serveur. '
            'Mettez-la à jour pour continuer à synchroniser.',
        clientVersion: schemaVersion,
        serverVersion: syncSchemaVersion,
      );
    }
    if (schemaVersion < minSupportedSchemaVersion) {
      throw SchemaVersionException(
        message:
            'Cette version du protocole de synchronisation n\'est plus '
            'supportée. Mettez votre application à jour.',
        clientVersion: schemaVersion,
        minSupported: minSupportedSchemaVersion,
      );
    }

    final DocumentId doc = DocumentId(docId);
    final AuthorId author = AuthorId(authorId);
    final Map<String, dynamic> payload = _requirePayload(json);

    return switch (type) {
      SyncOpTypes.insertBlock => InsertBlockOp(
        doc: doc,
        lamport: lamport,
        author: author,
        blockId: BlockId(_requireString(payload, 'block_id')),
        parent: payload['parent_id'] == null
            ? null
            : BlockId(_requireString(payload, 'parent_id')),
        order: _requireOrderKey(payload),
        type: _requireBlockType(payload),
        content: _requireContent(payload),
      ),
      SyncOpTypes.deleteBlock => DeleteBlockOp(
        doc: doc,
        lamport: lamport,
        author: author,
        blockId: BlockId(_requireString(payload, 'block_id')),
      ),
      SyncOpTypes.updateContent => UpdateContentOp(
        doc: doc,
        lamport: lamport,
        author: author,
        blockId: BlockId(_requireString(payload, 'block_id')),
        content: _requireContent(payload),
        base: _decodeBase(payload),
      ),
      SyncOpTypes.moveBlock => MoveBlockOp(
        doc: doc,
        lamport: lamport,
        author: author,
        blockId: BlockId(_requireString(payload, 'block_id')),
        parent: payload['parent_id'] == null
            ? null
            : BlockId(_requireString(payload, 'parent_id')),
        order: _requireOrderKey(payload),
      ),
      SyncOpTypes.setMeta => SetMetaOp(
        doc: doc,
        lamport: lamport,
        author: author,
        key: _requireString(payload, 'key'),
        value: _requireString(payload, 'value', allowEmpty: true),
      ),
      SyncOpTypes.addMark => AddMarkOp(
        doc: doc,
        lamport: lamport,
        author: author,
        markId: MarkId(_requireString(payload, 'mark_id')),
        blockId: BlockId(_requireString(payload, 'block_id')),
        type: _requireMarkType(payload),
        range: _requireRange(payload),
        body: payload['body'] is String ? payload['body']! as String : '',
      ),
      SyncOpTypes.removeMark => RemoveMarkOp(
        doc: doc,
        lamport: lamport,
        author: author,
        markId: MarkId(_requireString(payload, 'mark_id')),
        blockId: BlockId(_requireString(payload, 'block_id')),
      ),
      _ => throw ValidationException(
        field: 'type',
        message: 'Le type d\'opération « $type » est inconnu.',
      ),
    };
  }

  /// Decodes an operation read back from the journal.
  static SyncOp decodeRecord(SyncOpRecord record) {
    return decode(<String, dynamic>{
      'op_id': record.opId,
      'doc_id': record.docId,
      'lamport': record.lamport,
      'author_id': record.authorId,
      'type': record.type,
      'payload': record.payload,
      'schema_version': record.schemaVersion,
    });
  }

  /// Encodes one operation for the wire.
  static Map<String, Object?> encode(SyncOp op) {
    final Map<String, Object?> payload = switch (op) {
      InsertBlockOp(
        :final blockId,
        :final parent,
        :final order,
        :final type,
        :final content,
      ) =>
        <String, Object?>{
          'block_id': blockId.value,
          'parent_id': parent?.value,
          'order_key': order.value,
          'type': type.name,
          'content': content.plainText,
        },
      DeleteBlockOp(:final blockId) => <String, Object?>{
        'block_id': blockId.value,
      },
      UpdateContentOp(:final blockId, :final content) => <String, Object?>{
        'block_id': blockId.value,
        'content': content.plainText,
      },
      MoveBlockOp(:final blockId, :final parent, :final order) =>
        <String, Object?>{
          'block_id': blockId.value,
          'parent_id': parent?.value,
          'order_key': order.value,
        },
      SetMetaOp(:final key, :final value) => <String, Object?>{
        'key': key,
        'value': value,
      },
      AddMarkOp(
        :final markId,
        :final blockId,
        :final type,
        :final range,
        :final body,
      ) =>
        <String, Object?>{
          'mark_id': markId.value,
          'block_id': blockId.value,
          'type': type.name,
          'range': <String, Object?>{'start': range.start, 'end': range.end},
          'body': body,
        },
      RemoveMarkOp(:final markId, :final blockId) => <String, Object?>{
        'mark_id': markId.value,
        'block_id': blockId.value,
      },
    };

    return <String, Object?>{
      'op_id': op.operationKey,
      'doc_id': op.doc.value,
      'lamport': op.lamport,
      'author_id': op.author.value,
      'type': op.kind,
      'payload': payload,
      'schema_version': syncSchemaVersion,
    };
  }

  static String _requireString(
    Map<String, dynamic> json,
    String field, {
    bool allowEmpty = false,
  }) {
    final Object? value = json[field];
    if (value == null) {
      throw ValidationException(
        field: field,
        message: 'Le champ « $field » est obligatoire.',
      );
    }
    if (value is! String) {
      throw ValidationException(
        field: field,
        message: 'Le champ « $field » doit être une chaîne de caractères.',
      );
    }
    if (!allowEmpty && value.trim().isEmpty) {
      throw ValidationException(
        field: field,
        message: 'Le champ « $field » ne doit pas être vide.',
      );
    }
    return value;
  }

  static int _requireInt(Map<String, dynamic> json, String field) {
    final Object? value = json[field];
    if (value == null) {
      throw ValidationException(
        field: field,
        message: 'Le champ « $field » est obligatoire.',
      );
    }
    if (value is! int) {
      throw ValidationException(
        field: field,
        message: 'Le champ « $field » doit être un entier.',
      );
    }
    if (value < 0) {
      throw ValidationException(
        field: field,
        message: 'Le champ « $field » doit être positif ou nul.',
      );
    }
    return value;
  }

  static Map<String, dynamic> _requirePayload(Map<String, dynamic> json) {
    final Object? payload = json['payload'];
    if (payload == null) {
      throw const ValidationException(
        field: 'payload',
        message: 'Le champ « payload » est obligatoire.',
      );
    }
    if (payload is! Map<String, dynamic>) {
      throw const ValidationException(
        field: 'payload',
        message: 'Le champ « payload » doit être un objet JSON.',
      );
    }
    return payload;
  }

  static OrderKey _requireOrderKey(Map<String, dynamic> payload) {
    final String raw = _requireString(payload, 'order_key');
    try {
      return OrderKey(raw);
    } on InvalidSyncOperationException catch (error) {
      throw ValidationException(
        field: 'order_key',
        message: 'Le champ « order_key » n\'est pas une clé de tri valide.',
        details: <String, Object?>{'reason': error.message},
      );
    }
  }

  static BlockType _requireBlockType(Map<String, dynamic> payload) {
    final String raw = _requireString(payload, 'type');
    for (final BlockType type in BlockType.values) {
      if (type.name == raw) return type;
    }
    throw ValidationException(
      field: 'type',
      message: 'Le type de bloc « $raw » est inconnu.',
    );
  }

  static MarkType _requireMarkType(Map<String, dynamic> payload) {
    final String raw = _requireString(payload, 'type');
    for (final MarkType type in MarkType.values) {
      if (type.name == raw) return type;
    }
    throw ValidationException(
      field: 'type',
      message: 'Le type de marque « $raw » est inconnu.',
    );
  }

  static MarkRange _requireRange(Map<String, dynamic> payload) {
    final Object? range = payload['range'];
    if (range is! Map<String, dynamic>) {
      throw const ValidationException(
        field: 'range',
        message: 'Le champ « range » doit être un objet JSON.',
      );
    }
    final Object? start = range['start'];
    final Object? end = range['end'];
    if (start is! int || end is! int) {
      throw const ValidationException(
        field: 'range',
        message:
            'Le champ « range » doit porter les entiers « start » et '
            '« end ».',
      );
    }
    if (start < 0 || end < start) {
      throw const ValidationException(
        field: 'range',
        message: 'Le champ « range » doit décrire une plage valide.',
      );
    }
    return MarkRange(start: start, end: end);
  }

  static BlockContent _requireContent(Map<String, dynamic> payload) {
    final Object? content = payload['content'];
    if (content == null) {
      throw const ValidationException(
        field: 'content',
        message: 'Le champ « content » est obligatoire.',
      );
    }
    if (content is String) return TextContent(content);
    if (content is Map<String, dynamic>) {
      final Object? plainText = content['plain_text'];
      final Object? delta = content['delta_json'];
      if (plainText is String && delta is String) {
        return InlineContent(deltaJson: delta, plainText: plainText);
      }
    }
    throw const ValidationException(
      field: 'content',
      message:
          'Le champ « content » doit être une chaîne ou un objet '
          '« plain_text » / « delta_json ».',
    );
  }

  static ContentBase? _decodeBase(Map<String, dynamic> payload) {
    final Object? base = payload['base'];
    if (base == null) return null;
    if (base is! Map<String, dynamic>) {
      throw const ValidationException(
        field: 'base',
        message: 'Le champ « base » doit être un objet JSON.',
      );
    }
    final Object? lamport = base['lamport'];
    final Object? author = base['author'];
    if (lamport is! int || author is! String) {
      throw const ValidationException(
        field: 'base',
        message: 'Le champ « base » doit porter « lamport » et « author ».',
      );
    }
    return ContentBase(
      version: VersionRef(lamport: lamport, author: AuthorId(author)),
    );
  }
}
