import 'dart:convert';

import 'package:limpid_export/limpid_export.dart';
import 'package:test/test.dart';
import 'package:xml/xml.dart';

import 'cover_fixtures.dart';

void main() {
  group('CoverGenerator', () {
    test('la couverture porte le titre et l auteur', () async {
      final result = await generateCover(coverBook());

      final svg = utf8.decode(result.bytes);
      expect(svg, contains('Le Petit Livre'));
      expect(svg, contains('CAMILLE DUPONT'));
      expect(result.mimeType, 'image/svg+xml');
      expect(result.fileName, 'le-petit-livre-cover.svg');
    });

    test('les quatre variantes ont des dimensions differentes', () {
      final widths = <CoverVariant, double>{};
      final heights = <CoverVariant, double>{};

      for (final variant in CoverVariant.values) {
        final svg = const CoverGenerator().render(
          coverBook(),
          variant: variant,
        );
        final root = XmlDocument.parse(svg).rootElement;
        widths[variant] = double.parse(root.getAttribute('width')!);
        heights[variant] = double.parse(root.getAttribute('height')!);
      }

      // Le dos et la tranche sont etroits, la couverture complete est large.
      expect(
        widths[CoverVariant.spine]!,
        lessThan(widths[CoverVariant.front]!),
      );
      expect(
        widths[CoverVariant.back]!,
        greaterThan(widths[CoverVariant.front]!),
      );
      expect(
        widths[CoverVariant.full]!,
        greaterThan(widths[CoverVariant.front]!),
      );

      final foreEdge =
          widths[CoverVariant.full]! -
          widths[CoverVariant.back]! -
          widths[CoverVariant.spine]! -
          widths[CoverVariant.front]!;
      expect(foreEdge, greaterThan(0));
      expect(foreEdge, lessThan(widths[CoverVariant.spine]!));

      final sizes = <String>{
        for (final variant in CoverVariant.values)
          '${widths[variant]}x${heights[variant]}',
      };
      expect(sizes, hasLength(CoverVariant.values.length));
    });

    test('le meme livre donne deux fois la meme image', () async {
      final first = await generateCover(coverBook());
      final second = await generateCover(coverBook());

      expect(second.bytes, orderedEquals(first.bytes));
      expect(second.fileName, first.fileName);
    });

    test('deux livres differents n ont pas la meme palette', () {
      final first = CoverPalette.forBook(coverBook(identifier: 'livre-b'));
      final second = CoverPalette.forBook(coverBook(identifier: 'livre-c'));

      expect(first.index, isNot(second.index));
      expect(first.base, isNot(second.base));
      expect(first.shade, isNot(second.shade));
    });

    test('le meme livre garde toujours la meme palette', () {
      expect(
        CoverPalette.forBook(coverBook()).base,
        CoverPalette.forBook(coverBook()).base,
      );
    });

    test('les couleurs viennent des jetons du design system', () {
      final palette = CoverPalette.forBook(coverBook());

      expect(CoverTokens.palette, contains(palette.base));
      expect(palette.base, isNot(palette.shade));
      expect(palette.ink, CoverTokens.ink);
    });

    test('les polices de la couverture viennent du catalogue du paquet', () {
      expect(CoverTypography.isEmbedded(CoverTypography.titleFamily), isTrue);
      expect(CoverTypography.isEmbedded(CoverTypography.authorFamily), isTrue);
      expect(
        CoverTypography.titleStack,
        startsWith(CoverTypography.titleFamily),
      );
    });

    test('la couleur de la couverture suit l identite du livre', () {
      final seed = coverSeedOf(coverBook(identifier: 'projet-1'));
      final palette = CoverPalette.forBook(coverBook(identifier: 'projet-1'));

      expect(palette.seed, seed);
      expect(palette.index, seed % CoverTokens.palette.length);
    });
  });

  group('CoverImage', () {
    test('une couverture generee est une image SVG', () async {
      final image = await const CoverGenerator().generateImage(coverBook());

      expect(image.mimeType, 'image/svg+xml');
      expect(image.extension, 'svg');
      expect(image.fileName, 'images/le-petit-livre-cover.svg');
      expect(image.bytes, isNotEmpty);
    });
  });
}
