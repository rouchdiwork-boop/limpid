import 'dart:typed_data';

import '../model/export_book.dart';
import '../model/export_image.dart';
import '../model/export_options.dart';
import '../util/file_name.dart';
import '../util/zip_builder.dart';
import 'odt_content_xml.dart';
import 'odt_manifest_xml.dart';
import 'odt_meta_xml.dart';
import 'odt_namespaces.dart';
import 'odt_styles_xml.dart';

/// Generateur ODT (OpenDocument Text).
///
/// Le paquet est un ZIP dont la premiere entree, `mimetype`, est stockee
/// sans compression, conformement a la specification ODF.
class OdtWriter {
  /// Cree un generateur ODT.
  const OdtWriter({
    this.contentXml = const OdtContentXml(),
    this.stylesXml = const OdtStylesXml(),
    this.manifestXml = const OdtManifestXml(),
    this.metaXml = const OdtMetaXml(),
  });

  /// Generateur du contenu.
  final OdtContentXml contentXml;

  /// Generateur des styles.
  final OdtStylesXml stylesXml;

  /// Generateur du manifeste.
  final OdtManifestXml manifestXml;

  /// Generateur des metadonnees.
  final OdtMetaXml metaXml;

  /// Serialise le livre et renvoie les octets du paquet ODT.
  Future<Uint8List> write(ExportBook book, ExportOptions options) async {
    final images = <ExportImage, String>{};
    final payloads = <String, ExportImage>{};
    var imageIndex = 0;

    for (final chapter in book.chapters) {
      for (final block in chapter.blocks) {
        final image = block.image;
        if (image == null || images.containsKey(image)) {
          continue;
        }
        imageIndex++;
        final path = 'Pictures/image-$imageIndex.${image.extension}';
        images[image] = path;
        payloads[path] = image;
      }
    }

    String? coverPath;
    ExportImage? cover;
    if (options.includeCoverImage) {
      cover = book.coverImage;
      if (cover != null) {
        coverPath = 'Pictures/cover.${cover.extension}';
        payloads[coverPath] = cover;
      }
    }

    final entries = <String, String>{
      'content.xml': 'text/xml',
      'styles.xml': 'text/xml',
      'meta.xml': 'text/xml',
      for (final payload in payloads.entries)
        payload.key: payload.value.mimeType,
    };

    final zip = ZipBuilder()
      ..addString('mimetype', OdtNamespaces.mimeType, store: true)
      ..addString('META-INF/manifest.xml', manifestXml.render(entries))
      ..addString(
        'content.xml',
        contentXml.render(
          book,
          options,
          imagePaths: images,
          coverPath: coverPath,
        ),
      )
      ..addString('styles.xml', stylesXml.render(options))
      ..addString('meta.xml', metaXml.render(book));

    for (final payload in payloads.entries) {
      zip.addBytes(payload.key, payload.value.bytes);
    }

    return zip.build();
  }

  /// Nom de fichier recommande pour l'export ODT.
  static String fileNameFor(ExportBook book) =>
      FileNames.forBook(book.title, 'odt');

  /// Type MIME du fichier produit.
  static const String mimeType = OdtNamespaces.mimeType;
}
