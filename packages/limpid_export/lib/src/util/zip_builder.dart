import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';

/// Assemble un conteneur ZIP de facon deterministe.
///
/// Les entrees sont ecrites dans l'ordre d'insertion. Une entree peut etre
/// stockee sans compression, ce qui est impose par les specifications EPUB
/// (entree `mimetype`) et ODF (entree `mimetype`).
class ZipBuilder {
  final List<ArchiveFile> _entries = <ArchiveFile>[];

  /// Date utilisee pour toutes les entrees, afin de garantir un fichier
  /// reproductible.
  static final DateTime epoch = DateTime.utc(2020);

  /// Ajoute une entree binaire.
  ///
  /// Quand [store] est vrai, l'entree est ecrite sans compression.
  void addBytes(String name, List<int> bytes, {bool store = false}) {
    _entries.add(
      store
          ? ArchiveFile.noCompress(name, bytes.length, bytes)
          : ArchiveFile.bytes(name, bytes),
    );
  }

  /// Ajoute une entree texte (UTF-8).
  void addString(String name, String content, {bool store = false}) {
    addBytes(name, utf8.encode(content), store: store);
  }

  /// Nombre d'entrees ajoutees.
  int get length => _entries.length;

  /// Noms des entrees, dans l'ordre d'insertion.
  List<String> get names =>
      _entries.map((entry) => entry.name).toList(growable: false);

  /// Serialise l'archive.
  ///
  /// [modified] fixe l'horodatage de toutes les entrees ; a defaut, une date
  /// fixe est utilisee pour que le meme contenu produise le meme fichier.
  Uint8List build({DateTime? modified}) {
    final archive = Archive();
    for (final entry in _entries) {
      archive.add(entry);
    }
    final encoder = ZipEncoder();
    return encoder.encodeBytes(archive, modified: modified ?? epoch);
  }
}
