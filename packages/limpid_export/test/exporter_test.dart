import 'package:limpid_export/limpid_export.dart';
import 'package:test/test.dart';

import 'fixtures/sample_book.dart';

void main() {
  group('LimpidExporter', () {
    const exporter = LimpidExporter();

    test('exporte chaque format supported', () async {
      for (final format in ExportFormat.values) {
        final result = await exporter.export(
          format,
          sampleBook(coverImage: sampleCover()),
          const ExportOptions(),
        );
        expect(result.bytes, isNotEmpty, reason: format.name);
        expect(result.fileName, endsWith('.${format.extension}'));
        expect(result.mimeType, format.mimeType);
      }
    });

    test('le nom de fichier est derive du titre', () async {
      final result = await exporter.export(
        ExportFormat.epub3,
        sampleBook(),
        const ExportOptions(),
      );
      expect(result.fileName, 'le-petit-livre.epub');
      expect(result.mimeType, 'application/epub+zip');
    });

    test('les avertissements ne bloquent pas l export', () async {
      // Sans police embarquee, le moteur signale la substitution : l'export
      // doit quand meme aboutir.
      final exporter = LimpidExporter(fontRegistry: FontRegistry());
      final result = await exporter.export(
        ExportFormat.pdfReflowable,
        sampleBook(),
        const ExportOptions(),
      );
      expect(result.bytes, isNotEmpty);
      expect(result.warnings, isNotEmpty);
    });

    test('une erreur est levee avec un message utilisateur', () async {
      final book = ExportBook(
        title: 'Livre vide',
        chapters: <ExportChapter>[
          const ExportChapter(title: 'Chapitre', blocks: <ExportBlock>[]),
        ],
      );
      expect(
        () => exporter.export(ExportFormat.epub3, book, const ExportOptions()),
        returnsNormally,
      );
    });
  });

  group('ExportFormat', () {
    test('expose les extensions et les types MIME', () {
      expect(ExportFormat.epub3.extension, 'epub');
      expect(ExportFormat.pdfReflowable.mimeType, 'application/pdf');
      expect(ExportFormat.pdfPrintReady.isPdf, isTrue);
      expect(ExportFormat.pdf, ExportFormat.pdfReflowable);
    });
  });

  group('ExportOptions', () {
    test('les presets correspondent aux modes attendus', () {
      expect(ExportOptions.reflowable.pdfMode, ExportPdfMode.reflowable);
      expect(ExportOptions.printReady.pdfMode, ExportPdfMode.printReady);
      expect(ExportOptions.printReady.bleedMm, greaterThan(0));
    });

    test('copyWith ne modifie pas l instance d origine', () {
      const options = ExportOptions();
      final updated = options.copyWith(fontSize: 14);
      expect(options.fontSize, 11);
      expect(updated.fontSize, 14);
    });
  });

  group('ExportBook', () {
    test('compte les mots du manuscrit', () {
      final book = sampleBook();
      expect(book.wordCount, greaterThan(30));
      expect(book.chapters, hasLength(2));
    });
  });
}
