import 'dart:convert';
import 'dart:typed_data';

import 'package:pdf/widgets.dart' as pw;

import '../cover/cover_image.dart';
import '../model/export_image.dart';
import '../util/image_size.dart';
import 'pdf_cover_fonts.dart';
import 'pdf_svg.dart';

/// La couverture d'un livre, prete a etre dessinee dans un PDF.
///
/// Deux sources sont possibles : une image matricielle (une couverture
/// televersee) ou un document SVG (la couverture generee par le
/// generateur). Le SVG est dessine en vecteurs par le moteur PDF : il
/// n'est jamais rasterise, et le degrade comme les textes de la
/// couverture restent du vectoriel dans le fichier produit.
class PdfCover {
  /// Cree une couverture.
  const PdfCover({
    required this.bytes,
    required this.mimeType,
    required this.aspectRatio,
    this.svg,
    this.image,
  });

  /// Les octets de l'image ou du document SVG.
  final Uint8List bytes;

  /// Le type MIME de la couverture.
  final String mimeType;

  /// Le rapport largeur / hauteur de la couverture.
  final double aspectRatio;

  /// Le document SVG prepare, quand la couverture en est un.
  final PdfSvg? svg;

  /// L'image matricielle decodable, quand la couverture en est une.
  final pw.MemoryImage? image;

  /// Vrai quand la couverture est un document SVG.
  bool get isSvg => svg != null;

  /// Prepare la couverture d'une image du modele d'export.
  ///
  /// Renvoie `null` quand la couverture ne peut pas etre lue : une image
  /// d'un format inconnu, ou illisible, ou un SVG mal forme. L'export
  /// continue alors sans couverture, plutot que de produire une page
  /// blanche ou un fichier casse.
  static PdfCover? fromImage(ExportImage image) {
    if (image.mimeType == CoverImage.svgMimeType) {
      return _fromSvg(image.bytes);
    }
    return _fromRaster(image.bytes, image.mimeType);
  }

  static PdfCover? _fromSvg(Uint8List bytes) {
    final String source;
    try {
      source = utf8.decode(bytes, allowMalformed: true);
    } on Object {
      return null;
    }
    final prepared = PdfSvg.prepare(source);
    if (prepared == null) {
      return null;
    }
    return PdfCover(
      bytes: bytes,
      mimeType: CoverImage.svgMimeType,
      aspectRatio: prepared.aspectRatio,
      svg: prepared,
    );
  }

  static PdfCover? _fromRaster(Uint8List bytes, String mimeType) {
    final size = ImageSizes.of(bytes);
    if (size == null || size.aspectRatio <= 0) {
      return null;
    }
    try {
      return PdfCover(
        bytes: bytes,
        mimeType: mimeType,
        aspectRatio: size.aspectRatio,
        image: pw.MemoryImage(bytes),
      );
    } on Object {
      return null;
    }
  }

  /// Construit le widget de la couverture.
  ///
  /// Renvoie `null` quand la couverture ne peut pas etre dessinee ;
  /// l'avertissement est alors remis a [onWarning].
  pw.Widget? build({
    required PdfCoverFonts fonts,
    required void Function(String message) onWarning,
  }) {
    final document = svg;
    if (document != null) {
      return pw.SvgImage(svg: document.source, customFontLookup: fonts.lookup);
    }
    final picture = image;
    if (picture == null) {
      onWarning('Couverture ignoree : format non lisible.');
      return null;
    }
    return pw.Image(picture);
  }
}
