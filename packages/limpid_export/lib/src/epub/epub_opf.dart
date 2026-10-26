import '../model/export_book.dart';
import '../util/xml_writer.dart';

/// Element du manifeste EPUB.
class EpubOpfItem {
  /// Cree un element de manifeste.
  const EpubOpfItem({
    required this.id,
    required this.href,
    required this.mediaType,
    this.properties,
  });

  /// Identifiant unique de l'element dans le manifeste.
  final String id;

  /// Chemin relatif du fichier dans le paquet.
  final String href;

  /// Type MIME du fichier.
  final String mediaType;

  /// Proprietes EPUB (`nav`, `cover-image`, `scripted`...).
  final String? properties;
}

/// Generateur du paquet EPUB 3 (`content.opf`).
class EpubOpfWriter {
  const EpubOpfWriter();

  /// Namespace du paquet EPUB.
  static const String packageNamespace = 'http://www.idpf.org/2007/opf';

  /// Namespace Dublin Core.
  static const String dcNamespace = 'http://purl.org/dc/elements/1.1/';

  /// Serialise le paquet.
  String render({
    required ExportBook book,
    required String identifier,
    required DateTime modified,
    required List<EpubOpfItem> items,
    required List<String> spine,
  }) {
    final writer = XmlWriter();
    writer.element(
      'package',
      attributes: <String, String>{
        'xmlns': packageNamespace,
        'version': '3.0',
        'unique-identifier': 'pub-id',
        'xml:lang': book.language,
      },
      nest: () {
        _writeMetadata(writer, book, identifier, modified);
        writer.element(
          'manifest',
          nest: () {
            for (final item in items) {
              final properties = item.properties;
              writer.element(
                'item',
                attributes: <String, String>{
                  'id': item.id,
                  'href': item.href,
                  'media-type': item.mediaType,
                  'properties': ?properties,
                },
              );
            }
          },
        );
        writer.element(
          'spine',
          nest: () {
            for (final idref in spine) {
              writer.element(
                'itemref',
                attributes: <String, String>{'idref': idref},
              );
            }
          },
        );
      },
    );
    return writer.toXmlString();
  }

  void _writeMetadata(
    XmlWriter writer,
    ExportBook book,
    String identifier,
    DateTime modified,
  ) {
    final metadata = book.metadata;
    writer.element(
      'metadata',
      attributes: <String, String>{'xmlns:dc': dcNamespace},
      nest: () {
        writer.element(
          'dc:identifier',
          attributes: <String, String>{'id': 'pub-id'},
          nest: () => writer.text(identifier),
        );
        writer.element('dc:title', nest: () => writer.text(book.title));
        if (book.subtitle != null && book.subtitle!.isNotEmpty) {
          writer.element(
            'dc:title',
            attributes: <String, String>{'id': 'subtitle'},
            nest: () => writer.text(book.subtitle!),
          );
        }
        writer.element('dc:language', nest: () => writer.text(book.language));
        for (var index = 0; index < book.authors.length; index++) {
          writer.element(
            'dc:creator',
            attributes: <String, String>{'id': 'creator-${index + 1}'},
            nest: () => writer.text(book.authors[index]),
          );
          writer.element(
            'meta',
            attributes: <String, String>{
              'refines': '#creator-${index + 1}',
              'property': 'role',
              'scheme': 'marc:relators',
            },
            nest: () => writer.text('aut'),
          );
        }
        if (metadata.publisher != null) {
          writer.element(
            'dc:publisher',
            nest: () => writer.text(metadata.publisher!),
          );
        }
        if (metadata.description != null) {
          writer.element(
            'dc:description',
            nest: () => writer.text(metadata.description!),
          );
        }
        if (metadata.rights != null) {
          writer.element(
            'dc:rights',
            nest: () => writer.text(metadata.rights!),
          );
        }
        final date = metadata.publicationDate;
        if (date != null) {
          writer.element('dc:date', nest: () => writer.text(_formatDate(date)));
        }
        for (var index = 0; index < metadata.subjects.length; index++) {
          writer.element(
            'dc:subject',
            attributes: <String, String>{'id': 'subject-${index + 1}'},
            nest: () => writer.text(metadata.subjects[index]),
          );
        }
        for (final code in metadata.bisac) {
          writer.element(
            'meta',
            attributes: <String, String>{
              'property': 'subject',
              'scheme': 'onix:codelist5',
            },
            nest: () => writer.text(code),
          );
        }
        if (metadata.isbn != null && metadata.isbn!.isNotEmpty) {
          writer.element(
            'dc:identifier',
            attributes: <String, String>{'id': 'isbn'},
            nest: () => writer.text('urn:isbn:${metadata.isbn}'),
          );
          writer.element(
            'meta',
            attributes: <String, String>{
              'refines': '#isbn',
              'property': 'identifier-type',
              'scheme': 'onix:codelist5',
            },
            nest: () => writer.text('15'),
          );
        }
        writer.element(
          'meta',
          attributes: <String, String>{'property': 'dcterms:modified'},
          nest: () => writer.text(_formatDateTime(modified)),
        );
      },
    );
  }

  static String _formatDate(DateTime date) {
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    return '${date.year}-$month-$day';
  }

  static String _formatDateTime(DateTime date) {
    final datePart = _formatDate(date);
    final hours = date.hour.toString().padLeft(2, '0');
    final minutes = date.minute.toString().padLeft(2, '0');
    final seconds = date.second.toString().padLeft(2, '0');
    return '${datePart}T$hours:$minutes:${seconds}Z';
  }
}
