import 'dart:typed_data';

import 'package:limpid_export/limpid_export.dart';

/// Petit livre reel utilise comme fixture de test.
///
/// Deux chapitres, une citation, une liste, un bloc de code et une note de
/// bas de page : de quoi exercer tous les generateurs.
ExportBook sampleBook({ExportImage? coverImage}) {
  return ExportBook(
    title: 'Le Petit Livre',
    subtitle: 'Une histoire de nuit',
    authors: const <String>['Camille Dupont'],
    coverImage: coverImage,
    metadata: ExportMetadata(
      isbn: '978-2-1234-5678-9',
      description: 'Un petit livre écrit la nuit, dans une librairie.',
      publisher: 'Éditions Limpid',
      rights: '(c) 2026 Camille Dupont',
      publicationDate: DateTime.utc(2026, 1, 15),
      bisac: const <String>['FIC000000'],
      subjects: const <String>['Roman', 'Littérature'],
    ),
    chapters: <ExportChapter>[
      ExportChapter(
        title: 'Chapitre 1',
        identifier: 'chapitre-1',
        blocks: <ExportBlock>[
          const ExportBlock.paragraph(
            'Il était une fois une libraire qui écrivait des histoires la nuit.',
            footnotes: <String>[
              'La nuit, la librairie fermait à dix-neuf heures.',
            ],
          ),
          const ExportBlock.heading2('Le premier rayon'),
          const ExportBlock.paragraph(
            'Le premier rayon avait une particularité : ses livres ne se '
            'vendaient qu’aux lecteurs qui les cherchaient déjà.',
          ),
          const ExportBlock.quote(
            'Un livre vous attend, ou il ne vous attend pas.',
          ),
          const ExportBlock.listItem('Les romans courts'),
          const ExportBlock.listItem('Les poèmes'),
          const ExportBlock.code(
            'final nuit = DateTime.now();\n'
            'if (nuit.isAfter(DateTime(2026, 1, 15))) ecrire();',
            language: 'dart',
          ),
        ],
      ),
      ExportChapter(
        title: 'Chapitre 2',
        identifier: 'chapitre-2',
        blocks: <ExportBlock>[
          const ExportBlock.paragraph(
            'Au matin, la libraire retrouvait ses notes en ordre, et le lecteur '
            'ne savait rien du travail de la nuit.',
          ),
          const ExportBlock.paragraph(
            'Elle referma le cahier, venta la poussière, et alluma la lampe.',
          ),
        ],
      ),
    ],
  );
}

/// Couverture PNG de test (4 x 3 pixels).
Uint8List sampleCoverBytes() => Uint8List.fromList(_pngBytes());

List<int> _pngBytes() {
  return <int>[
    0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, //
    0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52,
    0x00, 0x00, 0x00, 0x04, 0x00, 0x00, 0x00, 0x03,
    0x08, 0x02, 0x00, 0x00, 0x00, 0x30, 0x16, 0x25,
    0x1C, 0xE8, 0x00, 0x00, 0x00, 0x18, 0x49, 0x44,
    0x41, 0x54, 0x78, 0x9C, 0x63, 0xF8, 0xCF, 0xC0,
    0xF0, 0x9F, 0x81, 0x81, 0x01, 0x00, 0x1B, 0x9D,
    0xF9, 0x2D, 0x0A, 0x00, 0x00, 0x00, 0x00, 0x49,
    0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82,
  ];
}

/// Couverture PNG de test, encapsulee dans un [ExportImage].
ExportImage sampleCover() {
  return ExportImage(
    bytes: sampleCoverBytes(),
    mimeType: 'image/png',
    altText: 'Couverture de test',
    fileName: 'cover.png',
  );
}
