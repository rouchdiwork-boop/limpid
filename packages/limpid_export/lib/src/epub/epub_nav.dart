import '../util/xml_writer.dart';
import 'epub_xhtml.dart';

/// Generateur de la navigation EPUB (`nav.xhtml`) et de la NCF de
/// compatibilite (`toc.ncx`).
class EpubNavWriter {
  const EpubNavWriter();

  /// Namespace NCX (compatibilite EPUB 2 / lecteurs anciens).
  static const String ncxNamespace = 'http://www.daisy.org/z3986/2005/ncx/';

  /// Serialise le document de navigation EPUB 3.
  String renderNav({
    required String bookTitle,
    required String language,
    required String cssHref,
    required List<EpubNavEntry> entries,
  }) {
    final writer = XmlWriter(doctype: 'html');
    writer.element(
      'html',
      attributes: <String, String>{
        'xmlns': EpubXhtmlWriter.xhtmlNamespace,
        'xmlns:epub': EpubXhtmlWriter.epubNamespace,
        'xml:lang': language,
        'lang': language,
      },
      nest: () {
        writer.element(
          'head',
          nest: () {
            writer.element(
              'meta',
              attributes: <String, String>{'charset': 'utf-8'},
            );
            writer.element(
              'title',
              nest: () => writer.text('Table des matieres'),
            );
            writer.element(
              'link',
              attributes: <String, String>{
                'rel': 'stylesheet',
                'type': 'text/css',
                'href': cssHref,
              },
            );
          },
        );
        writer.element(
          'body',
          nest: () {
            writer.element(
              'nav',
              attributes: <String, String>{'epub:type': 'toc', 'id': 'toc'},
              nest: () {
                writer.element(
                  'h1',
                  nest: () => writer.text('Table des matieres'),
                );
                writer.element(
                  'ol',
                  nest: () {
                    for (final entry in entries) {
                      writer.element(
                        'li',
                        nest: () {
                          writer.element(
                            'a',
                            attributes: <String, String>{'href': entry.href},
                            nest: () => writer.text(entry.title),
                          );
                        },
                      );
                    }
                  },
                );
              },
            );
            writer.element(
              'nav',
              attributes: <String, String>{
                'epub:type': 'landmarks',
                'id': 'landmarks',
                'hidden': 'hidden',
              },
              nest: () {
                writer.element(
                  'ol',
                  nest: () {
                    for (final entry in entries) {
                      writer.element(
                        'li',
                        nest: () {
                          writer.element(
                            'a',
                            attributes: <String, String>{
                              'epub:type': 'bodymatter',
                              'href': entry.href,
                            },
                            nest: () => writer.text('Debut du livre'),
                          );
                        },
                      );
                    }
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

  /// Serialise la table des matieres NCX (compatibilite).
  String renderNcx({
    required String bookTitle,
    required String identifier,
    required List<String> authors,
    required List<EpubNavEntry> entries,
  }) {
    final writer = XmlWriter();
    writer.element(
      'ncx',
      attributes: <String, String>{'xmlns': ncxNamespace, 'version': '2005-1'},
      nest: () {
        writer.element(
          'head',
          nest: () {
            writer.element(
              'meta',
              attributes: <String, String>{
                'name': 'dtb:uid',
                'content': identifier,
              },
            );
            writer.element(
              'meta',
              attributes: <String, String>{'name': 'dtb:depth', 'content': '1'},
            );
            writer.element(
              'meta',
              attributes: <String, String>{
                'name': 'dtb:totalPageCount',
                'content': '0',
              },
            );
            writer.element(
              'meta',
              attributes: <String, String>{
                'name': 'dtb:maxPageNumber',
                'content': '0',
              },
            );
          },
        );
        writer.element(
          'docTitle',
          nest: () {
            writer.element('text', nest: () => writer.text(bookTitle));
          },
        );
        for (final author in authors) {
          writer.element(
            'docAuthor',
            nest: () {
              writer.element('text', nest: () => writer.text(author));
            },
          );
        }
        writer.element(
          'navMap',
          nest: () {
            for (var index = 0; index < entries.length; index++) {
              final entry = entries[index];
              writer.element(
                'navPoint',
                attributes: <String, String>{
                  'id': 'navpoint-${index + 1}',
                  'playOrder': '${index + 1}',
                },
                nest: () {
                  writer.element(
                    'navLabel',
                    nest: () {
                      writer.element(
                        'text',
                        nest: () => writer.text(entry.title),
                      );
                    },
                  );
                  writer.element(
                    'content',
                    attributes: <String, String>{'src': entry.href},
                  );
                },
              );
            }
          },
        );
      },
    );
    return writer.toXmlString();
  }
}

/// Entree de navigation (chapitre) d'un EPUB.
class EpubNavEntry {
  /// Cree une entree de navigation.
  const EpubNavEntry({required this.title, required this.href});

  /// Titre affiche dans la table des matieres.
  final String title;

  /// Chemin relatif du fichier XHTML du chapitre.
  final String href;
}
