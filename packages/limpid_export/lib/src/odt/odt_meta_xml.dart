import '../model/export_book.dart';
import '../util/xml_writer.dart';
import 'odt_namespaces.dart';

/// Generateur du document `meta.xml` d'un paquet ODT.
class OdtMetaXml {
  const OdtMetaXml();

  /// Serialise les metadonnees du document.
  String render(ExportBook book) {
    final metadata = book.metadata;
    final writer = XmlWriter();
    writer.namespacedElement(
      'office:document-meta',
      namespaces: OdtNamespaces.all,
      attributes: <String, String>{'office:version': '1.3'},
      nest: () {
        writer.namespacedElement(
          'office:meta',
          nest: () {
            writer.namespacedElement(
              'dc:title',
              nest: () => writer.text(book.title),
            );
            if (book.subtitle != null) {
              writer.namespacedElement(
                'dc:subject',
                nest: () => writer.text(book.subtitle!),
              );
            }
            for (final author in book.authors) {
              writer.namespacedElement(
                'meta:initial-creator',
                nest: () => writer.text(author),
              );
            }
            if (metadata.description != null) {
              writer.namespacedElement(
                'dc:description',
                nest: () => writer.text(metadata.description!),
              );
            }
            if (metadata.publisher != null) {
              writer.namespacedElement(
                'dc:publisher',
                nest: () => writer.text(metadata.publisher!),
              );
            }
            if (metadata.rights != null) {
              writer.namespacedElement(
                'dc:rights',
                nest: () => writer.text(metadata.rights!),
              );
            }
            writer.namespacedElement(
              'dc:language',
              nest: () => writer.text(book.language),
            );
            final date = metadata.publicationDate;
            if (date != null) {
              writer.namespacedElement(
                'dc:date',
                nest: () => writer.text(_formatDate(date)),
              );
            }
            for (final subject in metadata.subjects) {
              writer.namespacedElement(
                'meta:keyword',
                nest: () => writer.text(subject),
              );
            }
            for (final code in metadata.bisac) {
              writer.namespacedElement(
                'meta:keyword',
                nest: () => writer.text(code),
              );
            }
            writer.namespacedElement(
              'meta:generator',
              nest: () => writer.text('Limpid'),
            );
          },
        );
      },
    );
    return writer.toXmlString();
  }

  static String _formatDate(DateTime date) {
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    return '${date.year}-$month-$day';
  }
}
