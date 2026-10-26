import 'dart:convert';

import 'package:limpid_export/limpid_export.dart';
import 'package:test/test.dart';
import 'package:xml/xml.dart';

import '../fixtures/sample_book.dart';
import '../support/zip_helpers.dart';
import 'cover_fixtures.dart';

void main() {
  group('CoveredExporter', () {
    test('l export EPUB embarque la couverture generee', () async {
      final exporter = CoveredExporter(export: const LimpidExporter().export);
      final result = await exporter(
        ExportFormat.epub3,
        coverBook(),
        const ExportOptions(),
      );

      final entries = readZipEntries(result.bytes);
      expect(entries.keys, contains('OEBPS/images/cover.svg'));

      final opf = readZipText(entries, 'OEBPS/content.opf');
      expect(opf, contains('properties="cover-image"'));
      expect(opf, contains('media-type="image/svg+xml"'));

      final cover = utf8.decode(entries['OEBPS/images/cover.svg']!);
      expect(cover, contains('Le Petit Livre'));
    });

    test('la couverture de face est le defaut', () async {
      final exporter = CoveredExporter(export: const LimpidExporter().export);
      final result = await exporter(
        ExportFormat.epub3,
        coverBook(),
        const ExportOptions(),
      );

      final entries = readZipEntries(result.bytes);
      final XmlDocument document = XmlDocument.parse(
        utf8.decode(entries['OEBPS/images/cover.svg']!),
      );

      // La couverture de face ne porte qu'une face : son gabarit est
      // celui d'une face de livre.
      expect(
        document.rootElement.getAttribute('width'),
        CoverSvgFormat.number(const CoverGeometry().faceWidth),
      );
    });

    test('la maquette complete porte le dos et la tranche', () async {
      final exporter = CoveredExporter.full(
        export: const LimpidExporter().export,
      );
      final result = await exporter(
        ExportFormat.epub3,
        coverBook(),
        const ExportOptions(),
      );

      final entries = readZipEntries(result.bytes);
      final String svg = utf8.decode(entries['OEBPS/images/cover.svg']!);
      final XmlDocument document = XmlDocument.parse(svg);

      // La maquette est plus large que la face : le dos et la tranche y
      // trouvent leur place.
      expect(
        document.rootElement.getAttribute('width'),
        CoverSvgFormat.number(
          const CoverGeometry().layoutOf(CoverVariant.full).width,
        ),
      );
      expect(
        int.parse(document.rootElement.getAttribute('width')!),
        greaterThan(const CoverGeometry().faceWidth),
      );

      // Le dos porte le titre tourne, le dos de couverture porte le
      // resume et l'editeur.
      expect(svg, contains('rotate(-90'));
      final String texts = document
          .findAllElements('text')
          .map((XmlElement element) => element.innerText)
          .join(' ');
      expect(texts, contains('Le Petit Livre'));
      expect(texts, contains('Editions Limpid'));
    });

    test('l export ODT embarque la couverture generee', () async {
      final exporter = CoveredExporter(export: const LimpidExporter().export);
      final result = await exporter(
        ExportFormat.odt,
        coverBook(),
        const ExportOptions(),
      );

      final entries = readZipEntries(result.bytes);
      expect(entries.keys, contains('Pictures/cover.svg'));
    });

    test('l export HTML reference la couverture generee', () async {
      final exporter = CoveredExporter(export: const LimpidExporter().export);
      final result = await exporter(
        ExportFormat.html,
        coverBook(),
        const ExportOptions(),
      );

      final html = utf8.decode(result.bytes);
      expect(html, contains('images/le-petit-livre-cover.svg'));
    });

    test('l export Markdown reference la couverture generee', () async {
      final exporter = CoveredExporter(export: const LimpidExporter().export);
      final result = await exporter(
        ExportFormat.markdown,
        coverBook(),
        const ExportOptions(),
      );

      final markdown = utf8.decode(result.bytes);
      expect(markdown, contains('![Couverture de Le Petit Livre]'));
      expect(markdown, contains('(images/le-petit-livre-cover.svg)'));
      expect(
        markdown.indexOf('![Couverture'),
        lessThan(markdown.indexOf('# ')),
      );
    });

    test('une couverture deja presente n est pas remplacee', () async {
      final existing = sampleCover();
      final book = coverBook().copyWith(coverImage: existing);

      final covered = await const CoverGenerator().attach(book);

      expect(covered.coverImage, same(existing));
    });

    test('une couverture existante peut etre remplacee', () async {
      final existing = sampleCover();
      final book = coverBook().copyWith(coverImage: existing);

      final covered = await const CoverGenerator().attach(
        book,
        replaceExisting: true,
      );

      expect(covered.coverImage, isNot(same(existing)));
      expect(covered.coverImage?.mimeType, 'image/svg+xml');
    });

    test('le livre couvert est copie, jamais modifie', () async {
      final book = coverBook();

      final covered = await const CoverGenerator().attach(book);

      expect(covered, isNot(same(book)));
      expect(book.coverImage, isNull);
      expect(covered.coverImage, isNotNull);
    });
  });
}
