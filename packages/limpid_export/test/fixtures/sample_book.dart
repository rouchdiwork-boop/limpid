import 'dart:typed_data';

import 'package:limpid_export/limpid_export.dart';

/// Petit livre reel utilise comme fixture de test.
///
/// Deux chapitres, une citation, une liste, un bloc de code et une note de
/// bas de page : de quoi exercer tous les generateurs.
///
/// L'ISBN par defaut est volontairement invalide : les tests qui ont
/// besoin d'un code-barres en fournissent un valide.
ExportBook sampleBook({ExportImage? coverImage, String? isbn}) {
  return ExportBook(
    title: 'Le Petit Livre',
    subtitle: 'Une histoire de nuit',
    authors: const <String>['Camille Dupont'],
    coverImage: coverImage,
    metadata: ExportMetadata(
      isbn: isbn ?? '978-2-1234-5678-9',
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
///
/// Le fichier est un PNG valide : il peut etre decode par les lecteurs
/// d'images, ce que le moteur PDF exige d'une couverture matricielle.
Uint8List sampleCoverBytes() => Uint8List.fromList(_pngBytes());

List<int> _pngBytes() {
  return <int>[
    0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, //
    0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52,
    0x00, 0x00, 0x00, 0x04, 0x00, 0x00, 0x00, 0x03,
    0x08, 0x02, 0x00, 0x00, 0x00, 0x3B, 0x96, 0x39,
    0x91, 0x00, 0x00, 0x00, 0x10, 0x49, 0x44, 0x41,
    0x54, 0x78, 0xDA, 0x63, 0x50, 0x48, 0x58, 0x00,
    0x47, 0x0C, 0x38, 0x39, 0x00, 0x01, 0x76, 0x0D,
    0x81, 0x9E, 0x05, 0x77, 0xEA, 0x00, 0x00, 0x00,
    0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60,
    0x82,
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
