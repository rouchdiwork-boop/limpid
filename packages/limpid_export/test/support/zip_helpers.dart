import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';

/// Lit les entrees d'un paquet ZIP.
Map<String, Uint8List> readZipEntries(List<int> bytes) {
  final archive = ZipDecoder().decodeBytes(bytes);
  return <String, Uint8List>{
    for (final file in archive.files)
      file.name: file.readBytes() ?? Uint8List(0),
  };
}

/// Lit une entree ZIP sous forme de texte UTF-8.
String readZipText(Map<String, Uint8List> entries, String name) {
  final content = entries[name];
  if (content == null) {
    throw StateError('Entree absente du paquet : $name');
  }
  return utf8.decode(content);
}

/// Indique si la premiere entree d'un ZIP est stockee sans compression.
///
/// La specification EPUB et la specification ODF imposent que l'entree
/// `mimetype` soit la premiere et ne soit pas compressee.
bool isFirstEntryStoredUncompressed(List<int> bytes) {
  if (bytes.length < 10) {
    return false;
  }
  final signature =
      bytes[0] | (bytes[1] << 8) | (bytes[2] << 16) | (bytes[3] << 24);
  const localHeaderSignature = 0x04034b50;
  if (signature != localHeaderSignature) {
    return false;
  }
  final method = bytes[8] | (bytes[9] << 8);
  return method == 0;
}
