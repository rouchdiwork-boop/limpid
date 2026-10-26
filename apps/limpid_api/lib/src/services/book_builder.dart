import 'package:limpid_core/limpid_core.dart';
import 'package:limpid_export/limpid_export.dart';

import '../db/project_record.dart';
import '../sync/tree_builder.dart';

/// Traduit l'etat CRDT d'un projet en livre exportable.
///
/// La traduction est la frontiere entre le modele de domaine de
/// `limpid_core` et le modele intermediaire de `limpid_export` : un
/// document synchronise (une scene) devient un chapitre.
abstract final class BookBuilder {
  /// Construit le livre de [project] a partir des [trees] reconstruits.
  ///
  /// [isbn] et [author] sont l'identite bibliographique de l'edition
  /// imprimee : ils sont poses quand ils sont connus, et laisses vides
  /// quand ils ne le sont pas. Un ISBN inconnu ne produit jamais de
  /// code-barres : l'export n'en fabrique aucun.
  static ExportBook build({
    required ProjectRecord project,
    required List<DocumentTree> trees,
    String? isbn,
    String? author,
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

    final String? knownIsbn = _clean(isbn);
    final String? knownAuthor = _clean(author);

    return ExportBook(
      title: project.title,
      authors: knownAuthor == null ? const <String>[] : <String>[knownAuthor],
      language: project.language,
      metadata: ExportMetadata(
        isbn: knownIsbn,
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

  /// La valeur [value] nettoyee, `null` quand elle ne porte rien.
  static String? _clean(String? value) {
    if (value == null) return null;
    final String trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
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
