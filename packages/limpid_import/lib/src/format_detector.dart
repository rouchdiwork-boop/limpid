import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';

import 'model/import_format.dart';
import 'model/import_request.dart';

/// La reconnaissance du format d'un fichier de manuscrit.
///
/// Le format est reconnu par l'extension du fichier, puis par son type MIME,
/// et en dernier ressort par les premiers octets du contenu : un fichier
/// dont le nom ne porte aucune information (un renvoi de telephone, une
/// piece jointe) reste lisible quand son contenu est sans ambiguite.
abstract final class ImportFormatDetector {
  /// Le type MIME du paquet EPUB.
  static const String epubMimeType = 'application/epub+zip';

  /// Le type MIME du paquet ODT.
  static const String odtMimeType = 'application/vnd.oasis.opendocument.text';

  /// Reconnaît le format de [request], `null` quand il est inconnu.
  ///
  /// Le nom du fichier passe avant le type MIME : c'est ce que l'auteur
  /// voit. Le type MIME tranche quand le nom ne dit rien.
  static ImportFormat? detect(ImportRequest request) {
    final ImportFormat? byExtension = ImportFormat.fromExtension(
      request.extension,
    );
    if (byExtension != null) return byExtension;

    final String? contentType = request.contentType;
    if (contentType != null && contentType.isNotEmpty) {
      final ImportFormat? byMime = ImportFormat.fromMimeType(contentType);
      if (byMime != null) return byMime;
    }

    return detectFromBytes(request.bytes);
  }

  /// Reconnaît le format dans les premiers octets de [bytes].
  ///
  /// Le contenu ne parle que de lui-meme quand il est sans ambiguite : un
  /// paquet ZIP est un DOCX, un ODT ou un EPUB, et le paquet dit lequel.
  static ImportFormat? detectFromBytes(Uint8List bytes) {
    if (bytes.length < 4) return null;

    if (_startsWith(bytes, <int>[0x7b, 0x5c, 0x72, 0x74, 0x66])) {
      return ImportFormat.rtf;
    }
    if (!_isZip(bytes)) return null;

    final Archive archive;
    try {
      archive = ZipDecoder().decodeBytes(bytes);
    } on Object {
      return null;
    }
    if (archive.findFile('META-INF/container.xml') != null) {
      return ImportFormat.epub;
    }
    final ArchiveFile? mimetype = archive.findFile('mimetype');
    if (mimetype != null) {
      final String? type = _textOf(mimetype);
      if (type == odtMimeType) return ImportFormat.odt;
    }
    if (archive.findFile('word/document.xml') != null) {
      return ImportFormat.docx;
    }
    return null;
  }

  static bool _isZip(Uint8List bytes) =>
      bytes[0] == 0x50 &&
      bytes[1] == 0x4b &&
      bytes[2] == 0x03 &&
      bytes[3] == 0x04;

  static bool _startsWith(Uint8List bytes, List<int> prefix) {
    if (bytes.length < prefix.length) return false;
    for (var i = 0; i < prefix.length; i++) {
      if (bytes[i] != prefix[i]) return false;
    }
    return true;
  }

  static String? _textOf(ArchiveFile file) {
    final Uint8List? content = file.readBytes();
    if (content == null) return null;
    return utf8.decode(content, allowMalformed: true).trim();
  }
}
