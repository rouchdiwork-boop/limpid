import 'dart:convert';

import '../errors.dart';

/// The payload of a block: either plain text or a rich inline document.
///
/// The rich variant stores the editor delta verbatim (as JSON) plus its plain
/// text projection, so that word counting and 3-way text merging never need
/// to understand the editor format. The `limpid_quill` adapter is responsible
/// for producing the delta.
sealed class BlockContent {
  /// Creates a block content.
  const BlockContent();

  /// The plain text projection of this content.
  String get plainText;

  /// Whether this content carries a rich inline document.
  bool get isRich => false;

  /// Returns a copy of this content with [text] as its plain text projection.
  ///
  /// Plain content is replaced outright; rich content keeps its delta and only
  /// refreshes the projection.
  BlockContent withPlainText(String text) => switch (this) {
    TextContent() => TextContent(text),
    InlineContent(:final deltaJson) => InlineContent(
      deltaJson: deltaJson,
      plainText: text,
    ),
  };
}

/// A content made of plain text.
final class TextContent extends BlockContent {
  /// Creates a plain-text content.
  const TextContent(this.text);

  /// The text of the block.
  final String text;

  @override
  String get plainText => text;

  @override
  bool operator ==(Object other) =>
      identical(this, other) || (other is TextContent && other.text == text);

  @override
  int get hashCode => Object.hash(TextContent, text);

  @override
  String toString() => 'TextContent(${text.length} chars)';
}

/// A content made of a rich inline document (editor delta encoded as JSON).
final class InlineContent extends BlockContent {
  /// Creates a rich content from an already computed plain text projection.
  const InlineContent({required this.deltaJson, required this.plainText});

  /// Builds a rich content from a Quill-like delta JSON document.
  ///
  /// Only `insert` operations carrying a string are projected to plain text;
  /// formatting attributes are ignored.
  ///
  /// Throws an [InvalidContentException] when [deltaJson] is not a valid
  /// delta document.
  factory InlineContent.fromDeltaJson(String deltaJson) {
    final Object? decoded;
    try {
      decoded = jsonDecode(deltaJson);
    } on FormatException catch (error) {
      throw InvalidContentException(
        'Delta is not valid JSON: ${error.message}',
      );
    }
    if (decoded is! Map<String, Object?>) {
      throw const InvalidContentException('Delta must be a JSON object.');
    }
    final ops = decoded['ops'];
    if (ops is! List<Object?>) {
      throw const InvalidContentException('Delta must contain an "ops" list.');
    }
    final buffer = StringBuffer();
    for (final op in ops) {
      if (op is! Map<String, Object?>) continue;
      final insert = op['insert'];
      if (insert is String) buffer.write(insert);
    }
    return InlineContent(deltaJson: deltaJson, plainText: buffer.toString());
  }

  /// The raw delta JSON document.
  final String deltaJson;

  @override
  final String plainText;

  @override
  bool get isRich => true;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is InlineContent &&
          other.deltaJson == deltaJson &&
          other.plainText == plainText);

  @override
  int get hashCode => Object.hash(InlineContent, deltaJson, plainText);

  @override
  String toString() => 'InlineContent(${plainText.length} chars)';
}
