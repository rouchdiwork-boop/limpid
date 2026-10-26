import '../model/export_book.dart';
import '../util/xml_writer.dart';
import 'cover_geometry.dart';
import 'cover_palette.dart';
import 'cover_svg_format.dart';
import 'cover_svg_panels.dart';
import 'cover_variant.dart';

/// Renders the cover of a book as an SVG document.
///
/// The rendering follows the cover of the application: a gradient drawn from
/// the palette of the book, the title anchored at the top of the face, the
/// author anchored at the bottom. A grain filter gives the sheet its
/// material: a cover is printed on paper, it is never a flat colour.
///
/// The document is deterministic: the same book always produces the same
/// bytes.
class CoverSvgWriter {
  /// Creates a writer.
  const CoverSvgWriter({this.panels = const CoverSvgPanels()});

  /// The panels of the cover.
  final CoverSvgPanels panels;

  /// The namespace of the SVG documents.
  static const String svgNamespace = 'http://www.w3.org/2000/svg';

  /// Renders the cover of [book].
  ///
  /// The variant decides which part of the wrap is drawn; [palette] and
  /// [geometry] allow the caller to override the colours and the print
  /// dimensions.
  String render(
    ExportBook book, {
    CoverVariant variant = CoverVariant.front,
    CoverPalette? palette,
    CoverGeometry geometry = const CoverGeometry(),
  }) {
    final colors = palette ?? CoverPalette.forBook(book);
    final layout = geometry.layoutOf(variant);
    final writer = XmlWriter();

    writer.element(
      'svg',
      attributes: <String, String>{
        'xmlns': svgNamespace,
        'width': CoverSvgFormat.number(layout.width),
        'height': CoverSvgFormat.number(layout.height),
        'viewBox':
            '0 0 ${CoverSvgFormat.number(layout.width)} '
            '${CoverSvgFormat.number(layout.height)}',
        'role': 'img',
        'aria-labelledby': 'cover-title cover-desc',
      },
      nest: () {
        _writeAccessibility(writer, book);
        _writeDefinitions(writer, colors);
        _writeBackground(writer, layout);
        switch (variant) {
          case CoverVariant.front:
            panels.writeFront(
              writer,
              book,
              colors,
              layout.panels.front,
              geometry,
            );
          case CoverVariant.back:
            panels.writeBack(
              writer,
              book,
              colors,
              layout.panels.back,
              geometry,
            );
          case CoverVariant.spine:
            panels.writeSpine(
              writer,
              book,
              colors,
              layout.panels.spine,
              geometry,
            );
          case CoverVariant.full:
            panels.writeBack(
              writer,
              book,
              colors,
              layout.panels.back,
              geometry,
            );
            panels.writeSpine(
              writer,
              book,
              colors,
              layout.panels.spine,
              geometry,
            );
            panels.writeFront(
              writer,
              book,
              colors,
              layout.panels.front,
              geometry,
            );
        }
        if (variant == CoverVariant.full) {
          _writeFolds(writer, colors, layout);
        }
      },
    );
    return writer.toXmlString();
  }

  void _writeAccessibility(XmlWriter writer, ExportBook book) {
    writer.element(
      'title',
      attributes: <String, String>{'id': 'cover-title'},
      nest: () => writer.text(book.title),
    );
    final author = CoverSvgPanels.authorOf(book);
    final description = author.isEmpty
        ? 'Couverture de ${book.title}.'
        : 'Couverture de ${book.title}, par $author.';
    writer.element(
      'desc',
      attributes: <String, String>{'id': 'cover-desc'},
      nest: () => writer.text(description),
    );
  }

  void _writeDefinitions(XmlWriter writer, CoverPalette colors) {
    writer.element(
      'defs',
      nest: () {
        writer.element(
          'linearGradient',
          attributes: <String, String>{
            'id': 'cover-gradient',
            'x1': '0',
            'y1': '0',
            'x2': '1',
            'y2': '1',
          },
          nest: () {
            writer.element(
              'stop',
              attributes: <String, String>{
                'offset': '0',
                'stop-color': colors.base,
              },
            );
            writer.element(
              'stop',
              attributes: <String, String>{
                'offset': '1',
                'stop-color': colors.shade,
              },
            );
          },
        );
        writer.element(
          'filter',
          attributes: <String, String>{
            'id': 'cover-grain',
            'x': '0',
            'y': '0',
            'width': '100%',
            'height': '100%',
            'color-interpolation-filters': 'sRGB',
          },
          nest: () {
            writer.element(
              'feTurbulence',
              attributes: <String, String>{
                'type': 'fractalNoise',
                'baseFrequency': '0.4',
                'numOctaves': '4',
                'seed': '${colors.seed}',
                'stitchTiles': 'stitch',
                'result': 'noise',
              },
            );
            writer.element(
              'feColorMatrix',
              attributes: <String, String>{
                'in': 'noise',
                'type': 'saturate',
                'values': '0',
                'result': 'mono',
              },
            );
            writer.element(
              'feComponentTransfer',
              attributes: <String, String>{'in': 'mono'},
              nest: () {
                writer.element(
                  'feFuncA',
                  attributes: <String, String>{
                    'type': 'linear',
                    'slope': '0.5',
                    'intercept': '0',
                  },
                );
              },
            );
          },
        );
      },
    );
  }

  void _writeBackground(XmlWriter writer, CoverLayout layout) {
    writer.element(
      'rect',
      attributes: <String, String>{
        'x': '0',
        'y': '0',
        'width': CoverSvgFormat.number(layout.width),
        'height': CoverSvgFormat.number(layout.height),
        'fill': 'url(#cover-gradient)',
      },
    );
    writer.element(
      'rect',
      attributes: <String, String>{
        'x': '0',
        'y': '0',
        'width': CoverSvgFormat.number(layout.width),
        'height': CoverSvgFormat.number(layout.height),
        'fill': '#000000',
        'filter': 'url(#cover-grain)',
        'opacity': '0.5',
      },
    );
  }

  void _writeFolds(XmlWriter writer, CoverPalette colors, CoverLayout layout) {
    final spine = layout.panels.spine;
    for (final x in <double>[spine.x, spine.right]) {
      writer.element(
        'rect',
        attributes: <String, String>{
          'x': CoverSvgFormat.number(x),
          'y': '0',
          'width': '2',
          'height': CoverSvgFormat.number(layout.height),
          'fill': colors.ink,
          'opacity': '0.22',
        },
      );
    }
  }
}
