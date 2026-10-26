import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_quill/flutter_quill.dart' show Attribute, BlockEmbed;
import 'package:flutter_quill/quill_delta.dart' show Delta, Operation;
import 'package:limpid_core/limpid_core.dart';

import 'scene_block.dart';

/// The key of the block attribute marking a scene separation.
///
/// The attribute is unknown to `flutter_quill`, which stores it as an
/// ignored attribute: it survives a round trip through the editor document
/// without polluting the Quill vocabulary.
const String kSceneBreakAttribute = 'scene-break';

/// The key of the block attribute marking a footnote.
const String kFootnoteAttribute = 'footnote';

/// One line of the manuscript editor.
///
/// A line carries its inline content — a [Delta] without its terminating
/// newline — and the kind of block it stands for.
@immutable
class LimpidEditorLine {
  /// Creates an editor line.
  const LimpidEditorLine({required this.content, required this.type});

  /// The inline content of the line, without its terminating newline.
  final Delta content;

  /// The kind of block the line stands for.
  final BlockType type;
}

/// Converts an editor delta into the rich content of a block.
///
/// The delta is stored verbatim as JSON, next to its plain text projection,
/// exactly as [InlineContent] expects it.
///
/// Throws an [InvalidContentException] when the delta cannot be encoded.
BlockContent deltaToBlockContent(Delta delta) {
  final String json = jsonEncode(<String, Object>{'ops': delta.toJson()});
  return InlineContent.fromDeltaJson(json);
}

/// Converts the rich content of a block back into an editor delta.
///
/// A plain content becomes a single insert operation; a rich content is
/// decoded from the JSON document it carries.
///
/// Throws a [FormatException] when the rich content is not a valid delta
/// document.
Delta blockContentToDelta(BlockContent content) => switch (content) {
  TextContent(:final String text) => Delta()..insert(text),
  InlineContent(:final String deltaJson) => _decodeDelta(deltaJson),
};

Delta _decodeDelta(String deltaJson) {
  final Object? decoded = jsonDecode(deltaJson);
  if (decoded is! Map<String, dynamic>) {
    throw const FormatException('A delta document must be a JSON object.');
  }
  final Object? ops = decoded['ops'];
  if (ops is! List) {
    throw const FormatException('A delta document must contain an "ops" list.');
  }
  return Delta.fromJson(ops);
}

/// Returns the kind of block described by the given block attributes.
///
/// The attributes of an unknown key are ignored: the editor only knows the
/// Quill vocabulary plus the two Limpid specific attributes.
BlockType blockTypeOf(Map<String, dynamic>? attributes) {
  if (attributes == null || attributes.isEmpty) {
    return BlockType.paragraph;
  }
  if (attributes.containsKey(kSceneBreakAttribute)) {
    return BlockType.sceneBreak;
  }
  if (attributes.containsKey(kFootnoteAttribute)) {
    return BlockType.footnote;
  }
  if (attributes.containsKey(Attribute.codeBlock.key)) {
    return BlockType.code;
  }
  if (attributes.containsKey(Attribute.blockQuote.key)) {
    return BlockType.quote;
  }
  final Object? header = attributes[Attribute.header.key];
  if (header is int) {
    return switch (header) {
      1 => BlockType.heading1,
      2 => BlockType.heading2,
      _ => BlockType.heading3,
    };
  }
  if (attributes.containsKey(Attribute.list.key)) {
    return BlockType.listItem;
  }
  return BlockType.paragraph;
}

/// Returns the block attributes describing the given kind of block.
///
/// A paragraph and an image carry no block attribute: the image is an
/// embedded object, not an attribute.
Map<String, dynamic> blockAttributesOf(BlockType type) => switch (type) {
  BlockType.paragraph || BlockType.image => const <String, dynamic>{},
  BlockType.heading1 => <String, dynamic>{Attribute.header.key: 1},
  BlockType.heading2 => <String, dynamic>{Attribute.header.key: 2},
  BlockType.heading3 => <String, dynamic>{Attribute.header.key: 3},
  BlockType.listItem => <String, dynamic>{Attribute.list.key: 'bullet'},
  BlockType.quote => <String, dynamic>{Attribute.blockQuote.key: true},
  BlockType.code => <String, dynamic>{Attribute.codeBlock.key: true},
  BlockType.footnote => <String, dynamic>{kFootnoteAttribute: true},
  BlockType.sceneBreak => <String, dynamic>{kSceneBreakAttribute: true},
};

/// Splits an editor document into its lines.
///
/// The block attributes of a line are carried by the newline that terminates
/// it, as in the Quill delta format; the inline attributes stay on the text
/// they decorate.
List<LimpidEditorLine> splitEditorLines(Delta document) {
  final List<LimpidEditorLine> lines = <LimpidEditorLine>[];
  Delta content = Delta();
  bool hasImage = false;

  void closeLine(Map<String, dynamic>? attributes) {
    lines.add(
      LimpidEditorLine(
        content: content,
        type: hasImage ? BlockType.image : blockTypeOf(attributes),
      ),
    );
    content = Delta();
    hasImage = false;
  }

  for (final Operation op in document.toList()) {
    if (!op.isInsert) {
      continue;
    }
    final Object? data = op.data;
    if (data is! String) {
      content.insert(data, _inlineAttributes(op.attributes));
      hasImage = hasImage || _isImageEmbed(data);
      continue;
    }
    final List<String> segments = data.split('\n');
    for (int i = 0; i < segments.length; i++) {
      if (i > 0) {
        closeLine(op.attributes);
      }
      if (segments[i].isNotEmpty) {
        content.insert(segments[i], _inlineAttributes(op.attributes));
      }
    }
  }
  if (content.isNotEmpty || lines.isEmpty) {
    lines.add(LimpidEditorLine(content: content, type: BlockType.paragraph));
  }
  return lines;
}

/// Converts an editor document into the blocks of a scene.
///
/// The identifiers and the fractional indices are produced by the caller, so
/// that the adapter stays deterministic and testable.
List<SceneBlock> deltaToSceneBlocks(
  Delta delta, {
  required BlockId Function(int index) blockIdAt,
  required OrderKey Function(int index) orderAt,
}) {
  final List<LimpidEditorLine> lines = splitEditorLines(delta);
  return List<SceneBlock>.generate(lines.length, (int index) {
    final LimpidEditorLine line = lines[index];
    return SceneBlock(
      id: blockIdAt(index),
      type: line.type,
      content: deltaToBlockContent(line.content),
      order: orderAt(index),
    );
  });
}

/// Converts the blocks of a scene back into an editor document.
///
/// The operations are pushed the way `flutter_quill` pushes them, so the
/// text and the newline of a plain paragraph are merged back into a single
/// operation: the document is byte for byte the one the editor produced.
Delta sceneBlocksToDelta(List<SceneBlock> blocks) {
  final Delta delta = Delta();
  for (final SceneBlock block in blocks) {
    for (final Operation op in blockContentToDelta(block.content).toList()) {
      delta.insert(op.data, op.attributes);
    }
    final Map<String, dynamic> attributes = blockAttributesOf(block.type);
    delta.insert('\n', attributes.isEmpty ? null : attributes);
  }
  return delta;
}

/// Generates the fractional indices of [count] sibling blocks.
///
/// Every key is strictly after the previous one, so the blocks keep the
/// order of the list without ever rewriting an existing key.
List<OrderKey> generateSceneOrders(int count) {
  final List<OrderKey> orders = <OrderKey>[];
  OrderKey? previous;
  for (int i = 0; i < count; i++) {
    previous = OrderKey.between(previous, null);
    orders.add(previous);
  }
  return orders;
}

/// Returns the number of characters covered by a delta.
int deltaCharacterLength(Delta delta) {
  int total = 0;
  for (final Operation op in delta.toList()) {
    total += op.length ?? 0;
  }
  return total;
}

Map<String, dynamic>? _inlineAttributes(Map<String, dynamic>? attributes) {
  if (attributes == null || attributes.isEmpty) {
    return null;
  }
  final Map<String, dynamic> inline = <String, dynamic>{};
  attributes.forEach((String key, dynamic value) {
    final Attribute? attribute = Attribute.fromKeyValue(key, value);
    if (attribute != null && attribute.isInline) {
      inline[key] = value;
    }
  });
  return inline.isEmpty ? null : inline;
}

bool _isImageEmbed(Object? data) =>
    data is Map && data.containsKey(BlockEmbed.imageType);
