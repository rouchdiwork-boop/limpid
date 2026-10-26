import '../model/export_options.dart';
import '../util/xml_writer.dart';
import 'odt_namespaces.dart';

/// Generateur du document `styles.xml` d'un paquet ODT.
class OdtStylesXml {
  const OdtStylesXml();

  /// Serialise les styles et la mise en page.
  String render(ExportOptions options) {
    final writer = XmlWriter();
    writer.namespacedElement(
      'office:document-styles',
      namespaces: OdtNamespaces.all,
      attributes: <String, String>{'office:version': '1.3'},
      nest: () {
        writer.namespacedElement(
          'office:styles',
          nest: () {
            writer.namespacedElement(
              'style:style',
              attributes: <String, String>{
                'style:name': 'Standard',
                'style:family': 'paragraph',
                'style:class': 'text',
              },
              nest: () {
                writer.namespacedElement(
                  'style:paragraph-properties',
                  attributes: <String, String>{
                    'fo:line-height': _lineHeight(options),
                    'fo:text-align': options.justifyText ? 'justify' : 'start',
                  },
                );
                writer.namespacedElement(
                  'style:text-properties',
                  attributes: <String, String>{
                    'fo:font-family': options.fontFamily,
                    'fo:font-size': '${options.fontSize}pt',
                    'fo:language': 'fr',
                  },
                );
              },
            );
            writer.namespacedElement(
              'style:style',
              attributes: <String, String>{
                'style:name': 'Standard',
                'style:family': 'graphic',
              },
              nest: () {
                writer.namespacedElement(
                  'style:graphic-properties',
                  attributes: <String, String>{
                    'draw:stroke': 'none',
                    'draw:fill': 'none',
                  },
                );
              },
            );
          },
        );
        writer.namespacedElement('office:automatic-styles');
        writer.namespacedElement(
          'office:master-styles',
          nest: () {
            writer.namespacedElement(
              'style:master-page',
              attributes: <String, String>{
                'style:name': 'Standard',
                'style:page-layout-name': 'PageLayout',
              },
              nest: () {
                writer.namespacedElement(
                  'style:page-layout',
                  attributes: <String, String>{'style:name': 'PageLayout'},
                  nest: () {
                    writer.namespacedElement(
                      'style:page-layout-properties',
                      attributes: <String, String>{
                        'fo:page-width': '${_cm(options.pageWidthMm)}cm',
                        'fo:page-height': '${_cm(options.pageHeightMm)}cm',
                        'fo:margin-top': '${_cm(options.marginTopMm)}cm',
                        'fo:margin-bottom': '${_cm(options.marginBottomMm)}cm',
                        'fo:margin-left': '${_cm(options.marginInsideMm)}cm',
                        'fo:margin-right': '${_cm(options.marginOutsideMm)}cm',
                        'style:print-orientation': 'portrait',
                      },
                    );
                  },
                );
              },
            );
          },
        );
      },
    );
    return writer.toXmlString();
  }

  static String _lineHeight(ExportOptions options) =>
      '${(options.lineHeight * 100).round()}%';

  static String _cm(double millimetres) =>
      (millimetres / 10).toStringAsFixed(2);
}
