import 'dart:typed_data';

/// Image binaire transportee dans le modele intermediaire d'export.
///
/// Les octets sont fournis tels quels par l'appelant : le moteur d'export ne
/// telecharge jamais d'image (contrainte hors-ligne).
class ExportImage {
  /// Cree une image a partir de ses octets.
  const ExportImage({
    required this.bytes,
    required this.mimeType,
    this.altText,
    this.fileName,
  });

  /// Contenu binaire de l'image.
  final Uint8List bytes;

  /// Type MIME de l'image (`image/jpeg`, `image/png`...).
  final String mimeType;

  /// Texte alternatif, utilise pour l'accessibilite.
  final String? altText;

  /// Nom de fichier suggere dans les archives (EPUB, ODT, DOCX).
  final String? fileName;

  /// Extension associee au type MIME, sans le point.
  String get extension {
    final separator = mimeType.indexOf('/');
    if (separator < 0 || separator == mimeType.length - 1) {
      return 'bin';
    }
    return mimeType.substring(separator + 1);
  }

  @override
  String toString() => 'ExportImage($mimeType, ${bytes.length} o)';
}
