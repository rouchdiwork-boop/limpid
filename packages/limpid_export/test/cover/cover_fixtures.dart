import 'package:limpid_export/limpid_export.dart';

/// Builds a book ready to be covered.
///
/// The identifier drives the palette of the cover: two books with two
/// identifiers keep two colours.
ExportBook coverBook({
  String identifier = 'livre-a',
  String title = 'Le Petit Livre',
  String author = 'Camille Dupont',
  String? subtitle = 'Une histoire de nuit',
  String? description = 'Un petit livre ecrit la nuit, dans une librairie.',
}) {
  return ExportBook(
    title: title,
    subtitle: subtitle,
    authors: <String>[author],
    metadata: ExportMetadata(
      identifier: identifier,
      description: description,
      publisher: 'Editions Limpid',
    ),
    chapters: <ExportChapter>[
      const ExportChapter(
        title: 'Chapitre 1',
        identifier: 'chapitre-1',
        blocks: <ExportBlock>[
          ExportBlock.paragraph('Il etait une fois une libraire.'),
        ],
      ),
    ],
  );
}
