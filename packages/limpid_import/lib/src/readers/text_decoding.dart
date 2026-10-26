import 'dart:convert';
import 'dart:typed_data';

/// Decode un fichier texte en ignorant les desaccords d'encodage.
///
/// Le texte est lu en UTF-8 : c'est l'encodage des fichiers Markdown, TXT et
/// XHTML. Un fichier qui n'est pas de l'UTF-8 valide est relu en latin-1,
/// ce qui ne perd aucun caractere : un fichier Word latin ne devient jamais
/// illisible.
String decodeText(Uint8List bytes) {
  final Uint8List payload = _withoutBom(bytes);
  try {
    return _normalizeNewLines(utf8.decode(payload));
  } on FormatException {
    return _normalizeNewLines(latin1.decode(payload));
  }
}

/// Retire le marqueur d'ordre des octets (BOM) d'un fichier UTF-8.
Uint8List _withoutBom(Uint8List bytes) {
  if (bytes.length >= 3 &&
      bytes[0] == 0xEF &&
      bytes[1] == 0xBB &&
      bytes[2] == 0xBF) {
    return Uint8List.sublistView(bytes, 3);
  }
  return bytes;
}

/// Normalise les fins de ligne sur le retour a la ligne simple.
String _normalizeNewLines(String text) =>
    text.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
