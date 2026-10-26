import 'dart:typed_data';

/// La demande d'import d'un manuscrit.
///
/// La demande porte le contenu du fichier et son nom : le nom sert a
/// reconnaitre le format et a nommer le manuscrit quand le fichier source ne
/// porte aucun titre.
final class ImportRequest {
  /// Cree une demande d'import.
  const ImportRequest({
    required this.fileName,
    required this.bytes,
    this.contentType,
  });

  /// Le nom du fichier, tel que l'appelant l'a fourni.
  final String fileName;

  /// Le contenu du fichier.
  final Uint8List bytes;

  /// Le type MIME annonce par l'appelant, `null` quand il est inconnu.
  final String? contentType;

  /// Le nom du fichier sans son extension.
  ///
  /// C'est le titre de repli du manuscrit : un fichier `mon-livre.docx` sans
  /// titre interne s'appelle « mon-livre ».
  String get baseName {
    final int dot = fileName.lastIndexOf('.');
    final String stem = dot <= 0 ? fileName : fileName.substring(0, dot);
    return stem.trim();
  }

  /// L'extension du fichier, sans le point, en minuscules.
  String get extension {
    final int dot = fileName.lastIndexOf('.');
    if (dot < 0 || dot == fileName.length - 1) return '';
    return fileName.substring(dot + 1).toLowerCase();
  }
}
