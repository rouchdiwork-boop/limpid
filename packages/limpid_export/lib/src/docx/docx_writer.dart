import 'dart:typed_data';

import '../model/export_book.dart';
import '../model/export_image.dart';
import '../model/export_options.dart';
import '../util/file_name.dart';
import '../util/image_size.dart';
import '../util/zip_builder.dart';
import 'docx_document_xml.dart';
import 'docx_footnotes_xml.dart';
import 'docx_numbering_xml.dart';
import 'docx_package.dart';
import 'docx_properties_xml.dart';
import 'docx_styles_xml.dart';

/// Generateur DOCX (WordprocessingML).
///
/// Le paquet OOXML est produit integralement par ce generateur : aucune
/// bibliotheque tierce n'est necessaire, et le resultat est deterministe.
class DocxWriter {
  /// Cree un generateur DOCX.
  const DocxWriter({
    this.documentXml = const DocxDocumentXml(),
    this.stylesXml = const DocxStylesXml(),
    this.numberingXml = const DocxNumberingXml(),
    this.footnotesXml = const DocxFootnotesXml(),
    this.propertiesXml = const DocxPropertiesXml(),
  });

  /// Generateur du corps du document.
  final DocxDocumentXml documentXml;

  /// Generateur des styles.
  final DocxStylesXml stylesXml;

  /// Generateur des listes.
  final DocxNumberingXml numberingXml;

  /// Generateur des notes de bas de page.
  final DocxFootnotesXml footnotesXml;

  /// Generateur des proprietes.
  final DocxPropertiesXml propertiesXml;

  /// Type MIME du document Word.
  static const String mimeType =
      'application/vnd.openxmlformats-officedocument.wordprocessingml.document';

  /// Serialise le livre et renvoie les octets du document Word.
  Future<Uint8List> write(ExportBook book, ExportOptions options) async {
    final images = <ExportImage, DocxImage>{};
    final payloads = <String, ExportImage>{};
    final relationships = <DocxRelationship>[
      const DocxRelationship(
        id: 'rId1',
        type: DocxPackage.stylesRelation,
        target: 'styles.xml',
      ),
      const DocxRelationship(
        id: 'rId2',
        type: DocxPackage.numberingRelation,
        target: 'numbering.xml',
      ),
      const DocxRelationship(
        id: 'rId3',
        type: DocxPackage.footnotesRelation,
        target: 'footnotes.xml',
      ),
    ];

    var imageIndex = 0;
    for (final chapter in book.chapters) {
      for (final block in chapter.blocks) {
        final image = block.image;
        if (image == null || images.containsKey(image)) {
          continue;
        }
        imageIndex++;
        final relationshipId = 'rId${imageIndex + 3}';
        final mediaPath = 'word/media/image$imageIndex.${image.extension}';
        final size = ImageSizes.of(image.bytes);
        images[image] = DocxDocumentXml.describeImage(
          relationshipId: relationshipId,
          pixelWidth: size?.width ?? 1600,
          pixelHeight: size?.height ?? 1000,
          maxWidthPt: DocxDocumentXml.contentWidthPt(options),
          dpi: options.imageDpi,
        );
        payloads[mediaPath] = image;
        relationships.add(
          DocxRelationship(
            id: relationshipId,
            type: DocxPackage.imageRelation,
            target: 'media/image$imageIndex.${image.extension}',
          ),
        );
      }
    }

    final footnotes = <String>[];
    final document = documentXml.render(
      book: book,
      options: options,
      footnotes: footnotes,
      images: images,
    );

    final modified =
        options.exportDate ??
        book.metadata.publicationDate ??
        DateTime.utc(2020);

    final zip = ZipBuilder()
      ..addString(
        '[Content_Types].xml',
        DocxPackage.contentTypes(
          hasImages: payloads.isNotEmpty,
          hasFootnotes: footnotes.isNotEmpty,
        ),
      )
      ..addString('_rels/.rels', DocxPackage.rootRelationships())
      ..addString('word/document.xml', document)
      ..addString('word/styles.xml', stylesXml.render(options))
      ..addString('word/numbering.xml', numberingXml.render())
      ..addString('word/footnotes.xml', footnotesXml.render(footnotes))
      ..addString(
        'word/_rels/document.xml.rels',
        DocxPackage.documentRelationships(relationships),
      )
      ..addString('docProps/core.xml', propertiesXml.renderCore(book, modified))
      ..addString('docProps/app.xml', propertiesXml.renderApp(book));

    for (final payload in payloads.entries) {
      zip.addBytes(payload.key, payload.value.bytes);
    }

    return zip.build();
  }

  /// Nom de fichier recommande pour l'export Word.
  static String fileNameFor(ExportBook book) =>
      FileNames.forBook(book.title, 'docx');
}
