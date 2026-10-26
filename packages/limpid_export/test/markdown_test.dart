import 'dart:convert';
import 'dart:io';

import 'package:limpid_export/limpid_export.dart';
import 'package:test/test.dart';

import 'fixtures/sample_book.dart';

void main() {
  group('Markdown', () {
    test('produit exactement la sortie de reference', () {
      final writer = const MarkdownWriter();
      final rendered = writer.render(sampleBook(), const ExportOptions());
      final golden = File('test/golden/sample_book.md').readAsStringSync();
      expect(_normalize(rendered), _normalize(golden));
    });

    test('le front matter contient les metadonnees du livre', () {
      final writer = const MarkdownWriter();
      final rendered = writer.render(sampleBook(), const ExportOptions());
      expect(rendered, startsWith('---\n'));
      expect(rendered, contains('title: "Le Petit Livre"'));
      expect(rendered, contains('author: "Camille Dupont"'));
      expect(rendered, contains('isbn: "978-2-1234-5678-9"'));
      expect(rendered, contains('description: "Un petit livre écrit la nuit'));
      expect(rendered, contains('date: 2026-01-15'));
    });

    test('les titres de chapitre sont de niveau 1', () {
      final writer = const MarkdownWriter();
      final rendered = writer.render(sampleBook(), const ExportOptions());
      expect(rendered, contains('# Chapitre 1'));
      expect(rendered, contains('# Chapitre 2'));
      expect(rendered, contains('## Le premier rayon'));
    });

    test('les citations, listes et blocs de code sont respectes', () {
      final writer = const MarkdownWriter();
      final rendered = writer.render(sampleBook(), const ExportOptions());
      expect(rendered, contains('> Un livre vous attend'));
      expect(rendered, contains('- Les romans courts'));
      expect(rendered, contains('```dart'));
      expect(rendered, contains('final nuit = DateTime.now();'));
    });

    test('les notes de bas de page sont definies', () {
      final writer = const MarkdownWriter();
      final rendered = writer.render(sampleBook(), const ExportOptions());
      expect(rendered, contains('[^1]'));
      expect(rendered, contains('[^1]: La nuit, la librairie fermait'));
    });

    test('les octets produits sont encodes en UTF-8', () async {
      final bytes = await const MarkdownWriter().write(
        sampleBook(),
        const ExportOptions(),
      );
      expect(bytes, isNotEmpty);
      expect(utf8.decode(bytes), contains('était'));
    });

    test('le nom de fichier est derive du titre', () {
      expect(MarkdownWriter.fileNameFor(sampleBook()), 'le-petit-livre.md');
    });
  });
}

String _normalize(String value) => value.replaceAll('\r\n', '\n');
