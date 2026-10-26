import 'dart:convert';

import 'package:limpid_export/limpid_export.dart';
import 'package:test/test.dart';

import 'fixtures/sample_book.dart';

void main() {
  group('HTML (ebook)', () {
    late String html;

    setUpAll(() {
      html = const HtmlWriter().renderEbook(
        sampleBook(),
        const ExportOptions(),
      );
    });

    test('produit un document HTML complet', () {
      expect(html, startsWith('<!DOCTYPE html>'));
      expect(html, contains('<html lang="fr">'));
      expect(html, contains('</html>'));
      expect(html, contains('<meta charset="utf-8">'));
    });

    test('contient les balises semantiques attendues', () {
      expect(html, contains('<article class="book">'));
      expect(html, contains('<section class="chapter"'));
      expect(html, contains('<h2 class="chapter-title">Chapitre 1</h2>'));
      expect(html, contains('<p>Il était une fois'));
      expect(html, contains('<blockquote>'));
      expect(html, contains('<ul>'));
      expect(html, contains('<pre><code>'));
      expect(html, contains('<style>'));
    });

    test('echappe le contenu du livre', () {
      final book = ExportBook(
        title: 'Titre & <balise>',
        chapters: <ExportChapter>[
          ExportChapter(
            title: 'Chapitre <script>',
            blocks: <ExportBlock>[
              const ExportBlock.paragraph('Un <script>alerte()</script> ici.'),
            ],
          ),
        ],
      );
      final rendered = const HtmlWriter().renderEbook(
        book,
        const ExportOptions(),
      );
      expect(rendered, contains('Titre &amp; &lt;balise&gt;'));
      expect(rendered, contains('Chapitre &lt;script&gt;'));
      expect(rendered, isNot(contains('<script>alerte()')));
      expect(rendered, contains('&lt;script&gt;alerte()&lt;/script&gt;'));
    });

    test('les notes de bas de page sont referencees', () {
      expect(html, contains('class="footnote-ref"'));
      expect(html, contains('id="note-1"'));
      expect(html, contains('La nuit, la librairie fermait'));
    });

    test('les octets produits sont encodes en UTF-8', () async {
      final bytes = await const HtmlWriter().write(
        sampleBook(),
        const ExportOptions(),
      );
      expect(utf8.decode(bytes), contains('était'));
    });
  });

  group('HTML (page de vente)', () {
    late String page;

    setUpAll(() {
      page = const HtmlSalesPageWriter().render(
        sampleBook(coverImage: sampleCover()),
        const ExportOptions(),
      );
    });

    test('contient les balises Open Graph', () {
      expect(page, contains('<meta property="og:type" content="book">'));
      expect(page, contains('property="og:title"'));
      expect(page, contains('property="og:description"'));
      expect(page, contains('property="og:image"'));
      expect(page, contains('property="og:locale"'));
      expect(page, contains('name="twitter:card"'));
    });

    test('contient un bloc JSON-LD de type Book', () {
      expect(page, contains('<script type="application/ld+json">'));
      expect(page, contains('"@type":"Book"'));
      expect(page, contains('"name":"Le Petit Livre"'));
      expect(page, contains('"isbn":"978-2-1234-5678-9"'));
      expect(page, contains('"@type":"Person"'));
      expect(page, contains('"inLanguage":"fr-FR"'));
    });

    test('le JSON-LD est du JSON valide', () {
      final start =
          page.indexOf('application/ld+json">') +
          'application/ld+json">'.length;
      final end = page.indexOf('</script>', start);
      final json = page.substring(start, end).trim();
      final decoded = jsonDecode(json);
      expect(decoded, isA<Map<String, dynamic>>());
      expect((decoded as Map<String, dynamic>)['@type'], 'Book');
    });

    test('le nom de fichier distingue la page de vente', () {
      expect(
        HtmlSalesPageWriter.fileNameFor(sampleBook()),
        'le-petit-livre-page-de-vente.html',
      );
    });
  });
}
