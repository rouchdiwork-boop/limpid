import 'package:limpid_export/limpid_export.dart';
import 'package:test/test.dart';
import 'package:xml/xml.dart';

import 'cover_fixtures.dart';

void main() {
  group('CoverSvgWriter', () {
    test('le SVG produit est bien forme', () {
      final svg = const CoverSvgWriter().render(coverBook());

      final document = XmlDocument.parse(svg);
      expect(document.rootElement.name.local, 'svg');
      expect(
        document.rootElement.name.namespaceUri,
        CoverSvgWriter.svgNamespace,
      );
      expect(document.rootElement.getAttribute('viewBox'), isNotEmpty);
    });

    test('le SVG porte le degrade et le grain de la couverture', () {
      final svg = const CoverSvgWriter().render(coverBook());

      expect(svg, contains('linearGradient'));
      expect(svg, contains('feTurbulence'));
      expect(svg, contains('url(#cover-gradient)'));
      expect(svg, contains('url(#cover-grain)'));
    });

    test('les textes du livre sont echappes', () {
      final svg = const CoverSvgWriter().render(
        coverBook(title: 'A < B & C > D', author: 'René & Co'),
      );

      expect(svg, isNot(contains('A < B')));
      final document = XmlDocument.parse(svg);
      final texts = document
          .findAllElements('text')
          .map((element) => element.innerText)
          .join(' ');
      expect(texts, contains('A < B & C > D'));
      expect(texts, contains('RENÉ & CO'));
    });

    test('le dos porte le texte tourne', () {
      final svg = const CoverSvgWriter().render(
        coverBook(),
        variant: CoverVariant.spine,
      );

      expect(svg, contains('rotate(-90'));
      expect(svg, contains('Le Petit Livre'));
    });

    test('la couverture complete reunit les trois panneaux', () {
      final svg = const CoverSvgWriter().render(
        coverBook(),
        variant: CoverVariant.full,
      );

      final document = XmlDocument.parse(svg);
      final texts = document
          .findAllElements('text')
          .map((element) => element.innerText)
          .join(' ');
      expect(texts, contains('Le Petit Livre'));
      expect(texts, contains('CAMILLE DUPONT'));
      expect(texts, contains('Editions Limpid'));
    });

    test('la couverture ne depend d aucun etat exterieur', () {
      final first = const CoverSvgWriter().render(coverBook());
      final second = const CoverSvgWriter().render(coverBook());

      expect(second, first);
    });
  });
}
