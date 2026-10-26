import 'dart:typed_data';

/// Dimensions en pixels d'une image.
class ImageSize {
  /// Cree des dimensions.
  const ImageSize(this.width, this.height);

  /// Largeur en pixels.
  final int width;

  /// Hauteur en pixels.
  final int height;

  /// Rapport largeur / hauteur (0 si la hauteur est nulle).
  double get aspectRatio => height == 0 ? 0 : width / height;

  @override
  String toString() => 'ImageSize(${width}x$height)';
}

/// Lecture des dimensions d'une image a partir de son en-tete.
///
/// Seuls les en-tetes sont lus : aucune image n'est decodee, ce qui evite un
/// cout memoire disproportionne pour les couvertures.
class ImageSizes {
  const ImageSizes._();

  /// Dimensions de l'image, ou `null` si le format n'est pas reconnu.
  static ImageSize? of(Uint8List bytes) {
    if (bytes.length < 16) {
      return null;
    }
    return _png(bytes) ??
        _jpeg(bytes) ??
        _gif(bytes) ??
        _bmp(bytes) ??
        _webp(bytes);
  }

  static ImageSize? _png(Uint8List bytes) {
    final signature = <int>[137, 80, 78, 71, 13, 10, 26, 10];
    for (var index = 0; index < signature.length; index++) {
      if (bytes[index] != signature[index]) {
        return null;
      }
    }
    if (bytes[12] != 73 ||
        bytes[13] != 72 ||
        bytes[14] != 68 ||
        bytes[15] != 82) {
      return null;
    }
    final width = _be32(bytes, 16);
    final height = _be32(bytes, 20);
    return width > 0 && height > 0 ? ImageSize(width, height) : null;
  }

  static ImageSize? _jpeg(Uint8List bytes) {
    if (bytes[0] != 0xFF || bytes[1] != 0xD8) {
      return null;
    }
    var index = 2;
    while (index + 9 < bytes.length) {
      if (bytes[index] != 0xFF) {
        index++;
        continue;
      }
      final marker = bytes[index + 1];
      if (marker == 0xD8 ||
          marker == 0x01 ||
          (marker >= 0xD0 && marker <= 0xD7)) {
        index += 2;
        continue;
      }
      final length = _be16(bytes, index + 2);
      final isStartOfFrame =
          marker >= 0xC0 &&
          marker <= 0xCF &&
          marker != 0xC4 &&
          marker != 0xC8 &&
          marker != 0xCC;
      if (isStartOfFrame) {
        final height = _be16(bytes, index + 5);
        final width = _be16(bytes, index + 7);
        return width > 0 && height > 0 ? ImageSize(width, height) : null;
      }
      index += 2 + length;
    }
    return null;
  }

  static ImageSize? _gif(Uint8List bytes) {
    final header = String.fromCharCodes(bytes.sublist(0, 6));
    if (header != 'GIF87a' && header != 'GIF89a') {
      return null;
    }
    final width = _le16(bytes, 6);
    final height = _le16(bytes, 8);
    return width > 0 && height > 0 ? ImageSize(width, height) : null;
  }

  static ImageSize? _bmp(Uint8List bytes) {
    if (bytes[0] != 0x42 || bytes[1] != 0x4D) {
      return null;
    }
    final width = _le32(bytes, 18);
    final rawHeight = _le32(bytes, 22);
    final height = rawHeight < 0 ? -rawHeight : rawHeight;
    return width > 0 && height > 0 ? ImageSize(width, height) : null;
  }

  static ImageSize? _webp(Uint8List bytes) {
    final riff = String.fromCharCodes(bytes.sublist(0, 4));
    final webp = String.fromCharCodes(bytes.sublist(8, 12));
    if (riff != 'RIFF' || webp != 'WEBP') {
      return null;
    }
    final chunk = String.fromCharCodes(bytes.sublist(12, 16));
    if (chunk == 'VP8X') {
      final width = 1 + (bytes[24] | (bytes[25] << 8) | (bytes[26] << 16));
      final height = 1 + (bytes[27] | (bytes[28] << 8) | (bytes[29] << 16));
      return width > 0 && height > 0 ? ImageSize(width, height) : null;
    }
    if (chunk == 'VP8 ') {
      final width = _le16(bytes, 26) & 0x3FFF;
      final height = _le16(bytes, 28) & 0x3FFF;
      return width > 0 && height > 0 ? ImageSize(width, height) : null;
    }
    return null;
  }

  static int _be16(Uint8List bytes, int offset) =>
      (bytes[offset] << 8) | bytes[offset + 1];

  static int _be32(Uint8List bytes, int offset) =>
      (bytes[offset] << 24) |
      (bytes[offset + 1] << 16) |
      (bytes[offset + 2] << 8) |
      bytes[offset + 3];

  static int _le16(Uint8List bytes, int offset) =>
      bytes[offset] | (bytes[offset + 1] << 8);

  static int _le32(Uint8List bytes, int offset) =>
      bytes[offset] |
      (bytes[offset + 1] << 8) |
      (bytes[offset + 2] << 16) |
      (bytes[offset + 3] << 24);
}
