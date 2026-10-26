import 'dart:typed_data';

import 'package:limpid_export/limpid_export.dart';
import 'package:test/test.dart';
import 'package:xml/xml.dart';

import 'fixtures/sample_book.dart';
import 'support/zip_helpers.dart';

void main() {
  group('DOCX', () {
    late Uint8List bytes;
    late Map<String, Uint8List> entries;

    setUpAll(() async {
      bytes = await const DocxWriter().write(
        sampleBook(),
        const ExportOptions(),
      );
      entries = readZipEntries(bytes);
    });

    test('produit un paquet ZIP non vide', () {
      expect(bytes.length, greaterThan(1000));
    });

    test('contient word/document.xml', () {
      expect(entries.keys, contains('word/document.xml'));
      final document = readZipText(entries, 'word/document.xml');
      expect(document, contains('<w:document'));
      expect(document, contains('<w:body>'));
    });

    test('contient les styles, les listes et les notes', () {
      expect(entries.keys, contains('word/styles.xml'));
      expect(entries.keys, contains('word/numbering.xml'));
      expect(entries.keys, contains('word/footnotes.xml'));
      expect(entries.keys, contains('docProps/core.xml'));
      expect(entries.keys, contains('docProps/app.xml'));
      expect(entries.keys, contains('[Content_Types].xml'));
    });

    test('definit les styles Titre 1/2/3 et Corps', () {
      final styles = readZipText(entries, 'word/styles.xml');
      expect(styles, contains('w:styleId="Heading1"'));
      expect(styles, contains('w:styleId="Heading2"'));
      expect(styles, contains('w:styleId="Heading3"'));
      expect(styles, contains('w:styleId="BodyText"'));
    });

    test('le document contient les titres et le texte du livre', () {
      final document = readZipText(entries, 'word/document.xml');
      expect(document, contains('Le Petit Livre'));
      expect(document, contains('w:val="Heading1"'));
      expect(document, contains('Il était une fois'));
      expect(document, contains('w:val="Quote"'));
      expect(document, contains('w:val="Code"'));
    });

    test('chaque chapitre est suivi d un saut de section', () {
      final document = readZipText(entries, 'word/document.xml');
      expect(document, contains('<w:sectPr>'));
      expect('w:sectPr'.allMatches(document).length, greaterThanOrEqualTo(2));
    });

    test('les notes de bas de page sont referencees et definies', () {
      final document = readZipText(entries, 'word/document.xml');
      expect(document, contains('<w:footnoteReference'));
      final footnotes = readZipText(entries, 'word/footnotes.xml');
      expect(footnotes, contains('La nuit, la librairie fermait'));
    });

    test('tous les documents XML du paquet sont bien formes', () {
      for (final name in <String>[
        '[Content_Types].xml',
        '_rels/.rels',
        'word/document.xml',
        'word/styles.xml',
        'word/numbering.xml',
        'word/footnotes.xml',
        'word/_rels/document.xml.rels',
        'docProps/core.xml',
        'docProps/app.xml',
      ]) {
        final document = XmlDocument.parse(readZipText(entries, name));
        expect(document.rootElement.name.local, isNotEmpty, reason: name);
      }
    });

    test('le nom de fichier est derive du titre', () {
      expect(DocxWriter.fileNameFor(sampleBook()), 'le-petit-livre.docx');
    });
  });
}
