import '../model/export_book.dart';
import '../util/xml_writer.dart';
import 'docx_package.dart';

/// Generateur des proprietes du document (`docProps/core.xml` et
/// `docProps/app.xml`).
class DocxPropertiesXml {
  const DocxPropertiesXml();

  /// Serialise `docProps/core.xml`.
  String renderCore(ExportBook book, DateTime modified) {
    final metadata = book.metadata;
    final writer = XmlWriter();
    writer.element(
      'cp:coreProperties',
      attributes: <String, String>{
        'xmlns:cp': DocxPackage.corePropertiesNamespace,
        'xmlns:dc': DocxPackage.dcNamespace,
        'xmlns:dcterms': DocxPackage.dctermsNamespace,
        'xmlns:xsi': DocxPackage.xsiNamespace,
      },
      nest: () {
        writer.element('dc:title', nest: () => writer.text(book.title));
        if (book.subtitle != null) {
          writer.element('dc:subject', nest: () => writer.text(book.subtitle!));
        }
        for (final author in book.authors) {
          writer.element('dc:creator', nest: () => writer.text(author));
        }
        if (metadata.description != null) {
          writer.element(
            'dc:description',
            nest: () => writer.text(metadata.description!),
          );
        }
        if (metadata.publisher != null) {
          writer.element(
            'dc:publisher',
            nest: () => writer.text(metadata.publisher!),
          );
        }
        if (metadata.rights != null) {
          writer.element(
            'dc:rights',
            nest: () => writer.text(metadata.rights!),
          );
        }
        writer.element('dc:language', nest: () => writer.text(book.language));
        if (metadata.isbn != null) {
          writer.element(
            'cp:keywords',
            nest: () => writer.text('ISBN ${metadata.isbn}'),
          );
        }
        writer.element('cp:revision', nest: () => writer.text('1'));
        final stamp = _formatDateTime(modified);
        writer.element(
          'dcterms:created',
          attributes: <String, String>{'xsi:type': 'dcterms:W3CDTF'},
          nest: () => writer.text(stamp),
        );
        writer.element(
          'dcterms:modified',
          attributes: <String, String>{'xsi:type': 'dcterms:W3CDTF'},
          nest: () => writer.text(stamp),
        );
      },
    );
    return writer.toXmlString();
  }

  /// Serialise `docProps/app.xml`.
  String renderApp(ExportBook book) {
    final writer = XmlWriter();
    writer.element(
      'Properties',
      attributes: <String, String>{
        'xmlns': DocxPackage.extendedPropertiesNamespace,
        'xmlns:vt':
            'http://schemas.openxmlformats.org/officeDocument/2006/docPropsVTypes',
      },
      nest: () {
        writer.element('Application', nest: () => writer.text('Limpid'));
        writer.element('AppVersion', nest: () => writer.text('1.0000'));
        final publisher = book.metadata.publisher;
        if (publisher != null) {
          writer.element('Company', nest: () => writer.text(publisher));
        }
        writer.element(
          'TitlesOfParts',
          nest: () {
            writer.element(
              'vt:vector',
              attributes: <String, String>{
                'size': '${book.chapters.length}',
                'baseType': 'lpstr',
              },
              nest: () {
                for (final chapter in book.chapters) {
                  writer.element(
                    'vt:lpstr',
                    nest: () => writer.text(chapter.title),
                  );
                }
              },
            );
          },
        );
      },
    );
    return writer.toXmlString();
  }

  static String _formatDateTime(DateTime date) {
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    final hours = date.hour.toString().padLeft(2, '0');
    final minutes = date.minute.toString().padLeft(2, '0');
    final seconds = date.second.toString().padLeft(2, '0');
    return '${date.year}-$month-$day'
        'T$hours:$minutes:${seconds}Z';
  }
}
