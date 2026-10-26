import 'dart:typed_data';

import 'package:limpid_export/limpid_export.dart';
import 'package:test/test.dart';
import 'package:xml/xml.dart';

import 'fixtures/sample_book.dart';
import 'support/zip_helpers.dart';

void main() {
  group('ODT', () {
    late Uint8List bytes;
    late Map<String, Uint8List> entries;

    setUpAll(() async {
      bytes = await const OdtWriter().write(
        sampleBook(coverImage: sampleCover()),
        const ExportOptions(),
      );
      entries = readZipEntries(bytes);
    });

    test('produit un paquet ZIP non vide', () {
      expect(bytes.length, greaterThan(1000));
    });

    test('contient une entree mimetype', () {
      expect(entries.keys, contains('mimetype'));
    });

    test('la premiere entree est mimetype, stockee sans compression', () {
      expect(isFirstEntryStoredUncompressed(bytes), isTrue);
      expect(entries.keys.first, 'mimetype');
    });

    test('contient le manifeste, le contenu et les styles', () {
      expect(entries.keys, contains('META-INF/manifest.xml'));
      expect(entries.keys, contains('content.xml'));
      expect(entries.keys, contains('styles.xml'));
      expect(entries.keys, contains('meta.xml'));
    });

    test('le manifeste declare les parties du paquet', () {
      final manifest = readZipText(entries, 'META-INF/manifest.xml');
      expect(manifest, contains('manifest:full-path="content.xml"'));
      expect(manifest, contains('manifest:full-path="styles.xml"'));
      expect(manifest, contains('Pictures/cover.png'));
    });

    test('le contenu contient les chapitres et les notes', () {
      final content = readZipText(entries, 'content.xml');
      expect(content, contains('<office:document-content'));
      expect(content, contains('<text:section'));
      expect(content, contains('Il était une fois'));
      expect(content, contains('<text:note'));
      expect(content, contains('La nuit, la librairie fermait'));
      expect(content, contains('draw:image'));
    });

    test('les styles definissent la police et la mise en page', () {
      final styles = readZipText(entries, 'styles.xml');
      expect(styles, contains('<office:document-styles'));
      expect(styles, contains('fo:font-family="Literata"'));
      expect(styles, contains('style:page-layout'));
    });

    test('tous les documents XML du paquet sont bien formes', () {
      for (final name in <String>[
        'META-INF/manifest.xml',
        'content.xml',
        'styles.xml',
        'meta.xml',
      ]) {
        final document = XmlDocument.parse(readZipText(entries, name));
        expect(document.rootElement.name.local, isNotEmpty, reason: name);
      }
    });

    test('le nom de fichier est derive du titre', () {
      expect(OdtWriter.fileNameFor(sampleBook()), 'le-petit-livre.odt');
    });
  });
}
