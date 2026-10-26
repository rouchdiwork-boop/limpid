import 'dart:convert';
import 'dart:typed_data';

import 'package:limpid_export/limpid_export.dart';
import 'package:test/test.dart';
import 'package:xml/xml.dart';

import 'fixtures/sample_book.dart';
import 'support/zip_helpers.dart';

void main() {
  late Uint8List bytes;

  setUpAll(() async {
    final writer = const Epub3Writer();
    bytes = await writer.write(
      sampleBook(coverImage: sampleCover()),
      const ExportOptions(),
    );
  });

  group('EPUB 3', () {
    test('produit un paquet ZIP non vide', () {
      expect(bytes.length, greaterThan(1000));
    });

    test('la premiere entree est mimetype, stockee sans compression', () {
      expect(isFirstEntryStoredUncompressed(bytes), isTrue);
      final entries = readZipEntries(bytes);
      expect(entries.keys.first, 'mimetype');
      expect(utf8.decode(entries['mimetype']!), 'application/epub+zip');
    });

    test('contient container.xml, content.opf, nav.xhtml et toc.ncx', () {
      final entries = readZipEntries(bytes);
      expect(entries.keys, contains('META-INF/container.xml'));
      expect(entries.keys, contains('OEBPS/content.opf'));
      expect(entries.keys, contains('OEBPS/nav.xhtml'));
      expect(entries.keys, contains('OEBPS/toc.ncx'));
      expect(entries.keys, contains('OEBPS/styles/epub.css'));
    });

    test('container.xml pointe vers le paquet OPF', () {
      final entries = readZipEntries(bytes);
      final container = readZipText(entries, 'META-INF/container.xml');
      expect(container, contains('full-path="OEBPS/content.opf"'));
      expect(container, contains('application/oebps-package+xml'));
    });

    test('content.opf declare le manifeste, la spine et Dublin Core', () {
      final entries = readZipEntries(bytes);
      final opf = readZipText(entries, 'OEBPS/content.opf');
      expect(opf, contains('<package'));
      expect(opf, contains('version="3.0"'));
      expect(opf, contains('<manifest>'));
      expect(opf, contains('<spine>'));
      expect(opf, contains('<dc:title>Le Petit Livre</dc:title>'));
      expect(opf, contains('<dc:language>fr-FR</dc:language>'));
      expect(opf, contains('<dc:creator'));
      expect(opf, contains('Camille Dupont'));
      expect(opf, contains('property="dcterms:modified"'));
    });

    test('content.opf contient les metadonnees ISBN et BISAC', () {
      final entries = readZipEntries(bytes);
      final opf = readZipText(entries, 'OEBPS/content.opf');
      expect(opf, contains('urn:isbn:978-2-1234-5678-9'));
      expect(opf, contains('identifier-type'));
      expect(opf, contains('FIC000000'));
      expect(opf, contains('onix:codelist5'));
      expect(opf, contains('<dc:subject'));
    });

    test('nav.xhtml liste les chapitres', () {
      final entries = readZipEntries(bytes);
      final nav = readZipText(entries, 'OEBPS/nav.xhtml');
      expect(nav, contains('epub:type="toc"'));
      expect(nav, contains('href="chapter-01.xhtml"'));
      expect(nav, contains('href="chapter-02.xhtml"'));
      expect(nav, contains('Chapitre 2'));
    });

    test('toc.ncx est une table des matieres NCX', () {
      final entries = readZipEntries(bytes);
      final ncx = readZipText(entries, 'OEBPS/toc.ncx');
      expect(ncx, contains('<ncx'));
      expect(ncx, contains('version="2005-1"'));
      expect(ncx, contains('<navMap>'));
      expect(ncx, contains('src="chapter-01.xhtml"'));
    });

    test('chaque chapitre est un document XHTML', () {
      final entries = readZipEntries(bytes);
      final chapter = readZipText(entries, 'OEBPS/chapter-01.xhtml');
      expect(chapter, contains('xmlns="http://www.w3.org/1999/xhtml"'));
      expect(chapter, contains('epub:type="chapter"'));
      expect(chapter, contains('Il était une fois'));
    });

    test('la couverture est embarquee et declaree', () {
      final entries = readZipEntries(bytes);
      expect(entries.keys, contains('OEBPS/images/cover.png'));
      final opf = readZipText(entries, 'OEBPS/content.opf');
      expect(opf, contains('properties="cover-image"'));
    });

    test('tous les documents XML du paquet sont bien formes', () {
      final entries = readZipEntries(bytes);
      for (final name in <String>[
        'META-INF/container.xml',
        'OEBPS/content.opf',
        'OEBPS/nav.xhtml',
        'OEBPS/toc.ncx',
        'OEBPS/chapter-01.xhtml',
        'OEBPS/chapter-02.xhtml',
      ]) {
        final document = XmlDocument.parse(readZipText(entries, name));
        expect(document.rootElement.name.local, isNotEmpty, reason: name);
      }
    });

    test('la spine suit l ordre des chapitres', () {
      final entries = readZipEntries(bytes);
      final opf = XmlDocument.parse(readZipText(entries, 'OEBPS/content.opf'));
      final spine = opf.rootElement.getElement('spine');
      expect(spine, isNotNull);
      final refs = spine!
          .findElements('itemref')
          .map((element) => element.getAttribute('idref'))
          .toList();
      expect(refs, <String>['chapter-1', 'chapter-2']);
    });

    test(
      'une illustration de chapitre est referencee en chemin relatif',
      () async {
        final book = ExportBook(
          title: 'Livre illustre',
          chapters: <ExportChapter>[
            ExportChapter(
              title: 'Chapitre 1',
              blocks: <ExportBlock>[
                ExportBlock.image(sampleCover(), altText: 'Une couverture'),
              ],
            ),
          ],
        );
        final illustrated = await const Epub3Writer().write(
          book,
          const ExportOptions(),
        );
        final entries = readZipEntries(illustrated);
        expect(entries.keys, contains('OEBPS/images/image-1.png'));
        final chapter = readZipText(entries, 'OEBPS/chapter-01.xhtml');
        expect(chapter, contains('src="images/image-1.png"'));
        final opf = readZipText(entries, 'OEBPS/content.opf');
        expect(opf, contains('href="images/image-1.png"'));
      },
    );
  });
}
