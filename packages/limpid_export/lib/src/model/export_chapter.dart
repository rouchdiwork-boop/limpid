import 'export_block.dart';

/// Chapitre d'un livre exportable.
///
/// Un chapitre est une vue ordonnee de blocs (cf. D-02 : la scene est l'unite
/// atomique de stockage, le chapitre une vue).
class ExportChapter {
  /// Cree un chapitre.
  const ExportChapter({
    required this.title,
    required this.blocks,
    this.order = 0,
    this.identifier,
  });

  /// Titre du chapitre.
  final String title;

  /// Blocs du chapitre, dans l'ordre de lecture.
  final List<ExportBlock> blocks;

  /// Rang du chapitre dans le livre (0 = premier).
  final int order;

  /// Identifiant stable, utilise comme ancre dans les formats lies (HTML,
  /// EPUB, ODT).
  final String? identifier;

  /// Copie immuable du chapitre.
  ExportChapter copyWith({
    String? title,
    List<ExportBlock>? blocks,
    int? order,
    String? identifier,
  }) {
    return ExportChapter(
      title: title ?? this.title,
      blocks: blocks ?? this.blocks,
      order: order ?? this.order,
      identifier: identifier ?? this.identifier,
    );
  }

  @override
  String toString() => 'ExportChapter($order, $title, ${blocks.length} blocs)';
}
