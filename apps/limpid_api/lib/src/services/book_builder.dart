import 'package:limpid_core/limpid_core.dart';
import 'package:limpid_export/limpid_export.dart';

import '../db/project_record.dart';
import '../sync/tree_builder.dart';

/// Translates the CRDT state of a project into an exportable book.
///
/// The translation is the boundary between the domain model of `limpid_core`
/// and the intermediate model of `limpid_export`: one synchronised document
/// (a scene) becomes one chapter.
abstract final class BookBuilder {
  /// Builds the book of [project] from the reconstructed [trees].
  static ExportBook build({
    required ProjectRecord project,
    required List<DocumentTree> trees,
  }) {
    final List<ExportChapter> chapters = <ExportChapter>[];
    var order = 0;
    for (final DocumentTree tree in trees) {
      final List<ExportBlock> blocks = tree.blocks
          .map(_buildBlocks)
          .expand((List<ExportBlock> items) => items)
          .toList(growable: false);
      if (blocks.isEmpty) continue;
      chapters.add(
        ExportChapter(
          title: tree.meta['title'] ?? 'Chapitre ${order + 1}',
          blocks: blocks,
          order: order,
          identifier: tree.docId,
        ),
      );
      order += 1;
    }

    return ExportBook(
      title: project.title,
      authors: const <String>[],
      language: project.language,
      metadata: ExportMetadata(
        description: project.synopsis.isEmpty ? null : project.synopsis,
        language: project.language,
        // The identifier of the project is the seed of the colour of the
        // cover: it is the very value the application hashes, so a book keeps
        // the same colour in the studio and in its exported cover.
        identifier: project.id,
      ),
      chapters: chapters,
    );
  }

  static List<ExportBlock> _buildBlocks(BlockNode node) {
    final List<ExportBlock> blocks = <ExportBlock>[];
    final String text = node.content.trim();
    final ExportBlockType? type = _mapType(node.type);

    if (type == ExportBlockType.image) {
      if (text.isNotEmpty) {
        blocks.add(ExportBlock.paragraph(text));
      }
      return blocks;
    }
    if (type == null || text.isEmpty) return blocks;

    blocks.add(
      ExportBlock(
        type: type,
        text: text,
        level: type == ExportBlockType.listItem ? _indentOf(node) : null,
      ),
    );
    for (final BlockNode child in node.children) {
      blocks.addAll(_buildBlocks(child));
    }
    return blocks;
  }

  static ExportBlockType? _mapType(String blockType) {
    for (final BlockType type in BlockType.values) {
      if (type.name != blockType) continue;
      return switch (type) {
        BlockType.paragraph => ExportBlockType.paragraph,
        BlockType.heading1 => ExportBlockType.heading1,
        BlockType.heading2 => ExportBlockType.heading2,
        BlockType.heading3 => ExportBlockType.heading3,
        BlockType.listItem => ExportBlockType.listItem,
        BlockType.quote => ExportBlockType.quote,
        BlockType.code => ExportBlockType.code,
        BlockType.image => ExportBlockType.image,
        BlockType.footnote => ExportBlockType.footnote,
        BlockType.sceneBreak => ExportBlockType.pageBreak,
      };
    }
    return null;
  }

  static int _indentOf(BlockNode node) {
    final int depth = node.orderKey.length;
    return depth <= 1 ? 1 : depth;
  }
}
