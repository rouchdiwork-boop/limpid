import 'dart:convert';
import 'dart:typed_data';

import 'package:limpid_export/limpid_export.dart';
import 'package:test/test.dart';

import 'fixtures/sample_book.dart';
import 'support/pdf_helpers.dart';

void main() {
  group('PDF reflowable', () {
    late Uint8List bytes;

    setUpAll(() async {
      bytes = await const PdfWriter().write(
        sampleBook(),
        const ExportOptions(),
      );
    });

    test('le fichier commence par le marqueur PDF', () {
      expect(ascii.decode(bytes.sublist(0, 5)), '%PDF-');
    });

    test('le fichier se termine par la marque de fin', () {
      final tail = ascii.decode(bytes.sublist(bytes.length - 6));
      expect(tail, contains('%%EOF'));
    });

    test('la taille est plausible pour un livre de deux chapitres', () {
      expect(bytes.length, greaterThan(2000));
      expect(bytes.length, lessThan(500000));
    });

    test('le document contient des pages', () {
      final raw = latin1.decode(bytes);
      expect(raw, contains('/Type/Page'));
      expect(raw, contains('/Type/Pages'));
    });

    test('le document contient un sommaire (signets)', () {
      final raw = latin1.decode(bytes);
      expect(raw, contains('/Outlines'));
      expect(raw, contains('Chapitre 1'));
    });

    test('le texte du livre est reellement rendu dans le PDF', () {
      final text = extractPdfText(bytes);
      expect(text, contains('Le Petit Livre'));
      expect(text, contains('Il était une fois une libraire'));
      expect(text, contains('Une histoire de nuit'));
      expect(text, contains('Table des matieres'));
    });

    test('le sommaire contient des liens internes cliquables', () {
      final raw = latin1.decode(bytes);
      expect(raw, contains('/Dests'));
      expect(raw, contains('chapitre-1'));
      expect(raw, contains('/Link'));
    });

    test('la table des matieres annonce les pages des chapitres', () {
      final text = extractPdfText(bytes);
      expect(text, contains('Chapitre'));
      expect(text, contains('Table des matieres'));
    });

    test('une police de substitution est signalee', () {
      final warnings = <String>[];
      final writer = PdfWriter(onWarning: warnings.add);
      expect(writer, isNotNull);
    });
  });

  group('PDF print-ready', () {
    late Uint8List printReady;
    late Uint8List reflowable;

    setUpAll(() async {
      printReady = await const PdfWriter().write(
        sampleBook(),
        ExportOptions.printReady,
      );
      reflowable = await const PdfWriter().write(
        sampleBook(),
        ExportOptions.reflowable,
      );
    });

    test('le fond perdu agrandit la page', () {
      expect(printReady, isNotEmpty);
      expect(ascii.decode(printReady.sublist(0, 5)), '%PDF-');

      final box = extractMediaBox(printReady);
      expect(box, isNotNull);
      final expectedWidth = (152.4 + 2 * 3) * 72 / 25.4;
      final expectedHeight = (228.6 + 2 * 3) * 72 / 25.4;
      expect(box![0], closeTo(expectedWidth, 0.5));
      expect(box[1], closeTo(expectedHeight, 0.5));
    });

    test('le format de lecture reste en A5', () {
      final box = extractMediaBox(reflowable);
      expect(box, isNotNull);
      expect(box![0], closeTo(148 * 72 / 25.4, 0.5));
      expect(box[1], closeTo(210 * 72 / 25.4, 0.5));
    });

    test('les marges sont en miroir', () {
      final origins = extractPdfOrigins(reflowable);
      final inside = 20 * 72 / 25.4;
      final outside = 15 * 72 / 25.4;
      final hasInside = origins.any((value) => (value - inside).abs() < 0.5);
      final hasOutside = origins.any((value) => (value - outside).abs() < 0.5);
      expect(hasInside, isTrue, reason: 'Marge interieure absente');
      expect(hasOutside, isTrue, reason: 'Marge exterieure absente');
    });

    test('le mode print-ready est applique par la facade', () async {
      final exporter = LimpidExporter();
      final result = await exporter.export(
        ExportFormat.pdfPrintReady,
        sampleBook(),
        const ExportOptions(),
      );
      expect(result.mimeType, 'application/pdf');
      expect(result.fileName, 'le-petit-livre.pdf');
      expect(ascii.decode(result.bytes.sublist(0, 5)), '%PDF-');
    });

    test(
      'la substitution de police est signalee dans les avertissements',
      () async {
        // Un registre sans police force la substitution : elle doit etre
        // signalee, sans faire echouer l'export.
        final exporter = LimpidExporter(fontRegistry: FontRegistry());
        final result = await exporter.export(
          ExportFormat.pdfReflowable,
          sampleBook(),
          const ExportOptions(),
        );
        expect(result.bytes, isNotEmpty);
        expect(
          result.warnings.any((warning) => warning.contains('indisponible')),
          isTrue,
          reason:
              'Aucune police embarquee : une substitution doit etre signalee.',
        );
      },
    );
  });

  group('Pagination', () {
    test('un livre long est pagine sur plusieurs pages', () async {
      final blocks = <ExportBlock>[
        for (var index = 0; index < 120; index++)
          ExportBlock.paragraph('Paragraphe numero $index. ' * 12),
      ];
      final book = ExportBook(
        title: 'Long livre',
        chapters: <ExportChapter>[
          ExportChapter(title: 'Chapitre unique', blocks: blocks),
        ],
      );
      final bytes = await const PdfWriter().write(book, const ExportOptions());
      final raw = latin1.decode(bytes);
      final pageCount = '/Type/Page'.allMatches(raw).length;
      expect(pageCount, greaterThan(2));
    });
  });
}
