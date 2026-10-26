import 'dart:typed_data';

import 'package:archive/archive.dart';

import '../model/import_exception.dart';

/// Un paquet ZIP ouvert en memoire.
///
/// Un DOCX, un ODT et un EPUB sont des paquets ZIP : ce paquet donne acces
/// aux entrees sans les ecrire sur le disque.
final class ZipPackage {
  ZipPackage._(this._archive);

  final Archive _archive;

  /// Ouvre le paquet porte par [bytes].
  ///
  /// Leve une [ImportException] quand le contenu n'est pas un paquet ZIP
  /// lisible.
  factory ZipPackage.open(Uint8List bytes) {
    final Archive archive;
    try {
      archive = ZipDecoder().decodeBytes(bytes);
    } on Object catch (error) {
      throw ImportException(
        ImportErrorCodes.unreadable,
        "Le fichier n'est pas un paquet que l'import sait ouvrir.",
        cause: error,
      );
    }
    return ZipPackage._(archive);
  }

  /// Les noms des entrees du paquet.
  List<String> get names => _archive.files
      .map((ArchiveFile file) => file.name)
      .toList(growable: false);

  /// Whether the package holds an entry named [name].
  bool has(String name) => _archive.findFile(name) != null;

  /// Le contenu de l'entree [name], `null` quand elle n'existe pas.
  Uint8List? file(String name) {
    final ArchiveFile? entry = _archive.findFile(name);
    if (entry == null || !entry.isFile) return null;
    return entry.readBytes();
  }

  /// The entries whose name starts with [prefix].
  ///
  /// Le prefixe est compare sans tenir compte de la casse.
  List<String> entriesUnder(String prefix) {
    final String needle = prefix.toLowerCase();
    return _archive.files
        .map((ArchiveFile file) => file.name)
        .where((String name) => name.toLowerCase().startsWith(needle))
        .toList(growable: false);
  }
}
