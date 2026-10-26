import 'dart:typed_data';

import 'package:limpid_export/limpid_export.dart';
import 'package:test/test.dart';

import '../fixtures/sample_book.dart';
import '../support/pdf_helpers.dart';

/// Un rectangle dessine dans un flux de contenu PDF.
class _Rect {
  const _Rect(this.left, this.top, this.width, this.height);

  final double left;
  final double top;
  final double width;
  final double height;
}

/// Les rectangles dessines dans un PDF.
List<_Rect> _rectsOf(Uint8List bytes) {
  final rects = <_Rect>[];
  final pattern = RegExp(r'([-0-9.]+) ([-0-9.]+) ([-0-9.]+) ([-0-9.]+) re');
  for (final stream in extractPdfStreams(bytes)) {
    for (final match in pattern.allMatches(stream)) {
      rects.add(
        _Rect(
          double.parse(match.group(1)!),
          double.parse(match.group(2)!),
          double.parse(match.group(3)!),
          double.parse(match.group(4)!),
        ),
      );
    }
  }
  return rects;
}

/// Les barres du code-barres : les rectangles dont la hauteur est celle
/// des barres.
List<_Rect> _barsOf(Uint8List bytes) {
  final barHeight = 22.85 * 72 / 25.4;
  return _rectsOf(bytes)
      .where((rect) => (rect.height - barHeight).abs() < 0.5)
      .toList(growable: false);
}

/// La largeur d'un module EAN-13, en points.
const double _moduleWidth = 0.33 * 72 / 25.4;

void main() {
  group('PDF code-barres', () {
    test(
      'un ISBN valide produit un code-barres sur la page de garde',
      () async {
        final bytes = await const PdfWriter().write(
          sampleBook(isbn: '9782123456780'),
          ExportOptions.printReady,
        );

        final symbol = Ean13.tryParse('9782123456780');
        expect(symbol, isNotNull);

        final bars = _barsOf(bytes);
        expect(bars.length, symbol!.runs.length);
        expect(bars, isNotEmpty);
      },
    );

    test('le code-barres respecte la largeur des modules', () async {
      final bytes = await const PdfWriter().write(
        sampleBook(isbn: '9782123456780'),
        ExportOptions.printReady,
      );

      final bars = _barsOf(bytes);
      final span = bars.last.left + bars.last.width - bars.first.left;
      expect(span, closeTo(Ean13.moduleCount * _moduleWidth, 0.1));
    });

    test('les chiffres du code-barres sont imprimes', () async {
      final bytes = await const PdfWriter().write(
        sampleBook(isbn: '9782123456780'),
        ExportOptions.printReady,
      );

      // Le code porte l'ISBN saisi : le prefixe n'est pas remplace.
      // La norme EAN-13 impose le groupement 1-6-6 : le premier chiffre
      // est imprime dans la zone de silence, a gauche du garde, et les
      // deux groupes de six sont alignes sur leurs barres. Le test
      // attend donc la forme groupee, pas la chaine continue.
      final text = extractPdfText(bytes);
      expect(
        RegExp(r'9\s+782123\s+456780').hasMatch(text),
        isTrue,
        reason:
            'Les chiffres doivent etre imprimes selon le groupement '
            '1-6-6 de la norme EAN-13.',
      );
      // Sans les espaces de groupement, ce sont bien les chiffres de
      // l'ISBN qui sont imprimes.
      expect(text.replaceAll(' ', ''), contains('9782123456780'));
    });

    test('le code-barres est imprime sur la couverture', () async {
      final bytes = await const PdfWriter().write(
        sampleBook(coverImage: sampleCover(), isbn: '9782123456780'),
        ExportOptions.printReady.copyWith(includeTitlePage: false),
      );

      final symbol = Ean13.tryParse('9782123456780');
      final bars = _barsOf(bytes);

      // La page de garde est absente : les barres qui restent sont celles
      // de la couverture.
      expect(bars, isNotEmpty);
      expect(bars.length, symbol!.runs.length);
    });

    test('la couverture sans ISBN ne porte aucun code-barres', () async {
      final warnings = <String>[];

      final bytes = await PdfWriter(onWarning: warnings.add).write(
        sampleBook(coverImage: sampleCover(), isbn: '   '),
        ExportOptions.printReady.copyWith(includeTitlePage: false),
      );

      expect(_barsOf(bytes), isEmpty);
      expect(
        warnings.any((warning) => warning.contains('couverture')),
        isTrue,
        reason: 'L absence d ISBN doit etre signalee sur la couverture.',
      );
    });

    test(
      'sans ISBN, le code-barres est omis et l absence est signalee',
      () async {
        final warnings = <String>[];

        final bytes = await PdfWriter(
          onWarning: warnings.add,
        ).write(sampleBook(isbn: '   '), ExportOptions.printReady);

        expect(_barsOf(bytes), isEmpty);
        expect(
          warnings.any((warning) => warning.contains('ISBN')),
          isTrue,
          reason: 'L absence d ISBN doit etre signalee.',
        );
      },
    );

    test('un ISBN invalide est signale, sans code-barres', () async {
      final warnings = <String>[];

      final bytes = await PdfWriter(
        onWarning: warnings.add,
      ).write(sampleBook(isbn: '978-2-1234-5678-9'), ExportOptions.printReady);

      expect(_barsOf(bytes), isEmpty);
      expect(
        warnings.any((warning) => warning.contains('invalide')),
        isTrue,
        reason: 'Un ISBN invalide doit etre signale.',
      );
    });

    test('le PDF de lecture ne porte pas de code-barres', () async {
      final warnings = <String>[];

      final bytes = await PdfWriter(
        onWarning: warnings.add,
      ).write(sampleBook(isbn: '9782123456780'), const ExportOptions());

      expect(_barsOf(bytes), isEmpty);
      expect(
        warnings.any((warning) => warning.contains('code-barres')),
        isFalse,
        reason: 'Le code-barres ne concerne que l edition imprimee.',
      );
    });

    test('le PDF reste valide sans code-barres', () async {
      final bytes = await const PdfWriter().write(
        sampleBook(isbn: '9782123456780'),
        ExportOptions.printReady,
      );

      expect(bytes.length, greaterThan(2000));
    });
  });
}
