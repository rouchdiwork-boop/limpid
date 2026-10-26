import 'dart:convert';
import 'dart:typed_data';

import 'package:limpid_export/limpid_export.dart';
import 'package:test/test.dart';

import '../fixtures/sample_book.dart';
import '../support/pdf_helpers.dart';

/// Le nombre de pages d'un PDF produit par le moteur.
int _pageCount(Uint8List bytes) => PdfDocument.read(bytes).pageCount;

/// Vrai quand le PDF contient une image matricielle.
///
/// L'image peut etre decrite dans le corps du fichier ou dans un flux
/// compresse : les deux sont parcourus.
bool _hasRasterImage(Uint8List bytes) {
  final pattern = RegExp(r'/(Type|Subtype)\s*/Image');
  if (pattern.hasMatch(latin1.decode(bytes, allowInvalid: true))) {
    return true;
  }
  for (final stream in extractPdfStreams(bytes)) {
    if (pattern.hasMatch(stream)) {
      return true;
    }
  }
  return false;
}

/// Le texte lisible d'un PDF.
String _textOf(Uint8List bytes) => extractPdfText(bytes);

void main() {
  group('PDF couverture', () {
    test('le PDF embarque la couverture generee', () async {
      final book = sampleBook();
      final covered = book.copyWith(
        coverImage: await const CoverGenerator().generateImage(book),
      );

      final withCover = await const PdfWriter().write(
        covered,
        const ExportOptions(),
      );
      final withoutCover = await const PdfWriter().write(
        book,
        const ExportOptions(),
      );

      expect(
        _pageCount(withCover),
        _pageCount(withoutCover) + 1,
        reason: 'La couverture doit ajouter une page.',
      );
    });

    test('la couverture generee est dessinee en vecteurs', () async {
      final book = sampleBook();
      final covered = book.copyWith(
        coverImage: await const CoverGenerator().generateImage(book),
      );

      final bytes = await const PdfWriter().write(
        covered,
        const ExportOptions(),
      );

      expect(
        _hasRasterImage(bytes),
        isFalse,
        reason: 'La couverture SVG ne doit pas etre rasterisee.',
      );
      expect(
        _textOf(bytes),
        contains('CAMILLE DUPONT'),
        reason: 'Le texte de la couverture doit etre rendu.',
      );
    });

    test('une couverture matricielle est embarquee comme image', () async {
      final bytes = await const PdfWriter().write(
        sampleBook(coverImage: sampleCover()),
        const ExportOptions(),
      );

      expect(_hasRasterImage(bytes), isTrue);
    });

    test('la couverture peut etre exclue', () async {
      final book = sampleBook(coverImage: sampleCover());

      final withCover = await const PdfWriter().write(
        book,
        const ExportOptions(),
      );
      final withoutCover = await const PdfWriter().write(
        book,
        const ExportOptions().copyWith(includeCoverImage: false),
      );

      expect(_pageCount(withoutCover), _pageCount(withCover) - 1);
      expect(_hasRasterImage(withoutCover), isFalse);
    });

    test('un livre sans couverture reste valide', () async {
      final bytes = await const PdfWriter().write(
        sampleBook(),
        const ExportOptions(),
      );

      expect(ascii.decode(bytes.sublist(0, 5)), '%PDF-');
      expect(ascii.decode(bytes.sublist(bytes.length - 6)), contains('%%EOF'));
    });

    test(
      'une couverture illisible est signalee, sans casser l export',
      () async {
        final broken = ExportImage(
          bytes: Uint8List.fromList(<int>[1, 2, 3, 4, 5]),
          mimeType: 'image/png',
          altText: 'couverture cassee',
        );
        final warnings = <String>[];

        final bytes = await PdfWriter(
          onWarning: warnings.add,
        ).write(sampleBook(coverImage: broken), const ExportOptions());
        final withoutCover = await const PdfWriter().write(
          sampleBook(),
          const ExportOptions(),
        );

        expect(ascii.decode(bytes.sublist(0, 5)), '%PDF-');
        expect(
          _pageCount(bytes),
          _pageCount(withoutCover),
          reason: 'Une couverture illisible ne doit pas laisser de page vide.',
        );
        expect(
          warnings.any((warning) => warning.contains('Couverture')),
          isTrue,
          reason: 'Une couverture illisible doit etre signalee.',
        );
      },
    );
  });
}
