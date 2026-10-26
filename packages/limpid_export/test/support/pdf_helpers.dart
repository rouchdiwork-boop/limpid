import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';

/// Texte contenu dans les flux de contenu d'un PDF.
///
/// Les flux sont compresses (Flate) : ils sont decompresses a la volee, puis
/// les chaines de texte (`[(...)]TJ`) sont concatenees. Le resultat est
/// lisible comme du Latin-1 (encodage WinAnsi des polices de base 14).
String extractPdfText(Uint8List bytes) {
  final raw = latin1.decode(bytes, allowInvalid: true);
  final builder = StringBuffer();
  final pattern = RegExp('stream\r?\n');
  for (final match in pattern.allMatches(raw)) {
    final start = match.end;
    final end = raw.indexOf('endstream', start);
    if (end < 0) {
      continue;
    }
    final payload = latin1.encode(raw.substring(start, end));
    builder.write(_extractStrings(_inflate(payload)));
  }
  return builder.toString();
}

/// Concatene les chaines de texte d'un flux de contenu PDF.
String _extractStrings(String stream) {
  final builder = StringBuffer();
  final pattern = RegExp(r'\[\((.*?)\)\]TJ');
  for (final match in pattern.allMatches(stream)) {
    builder.write(match.group(1));
    builder.write(' ');
  }
  return builder.toString();
}

String _inflate(List<int> payload) {
  try {
    return latin1.decode(
      const ZLibDecoder().decodeBytes(payload),
      allowInvalid: true,
    );
  } on Object {
    return '';
  }
}

/// Abscisses des translations de corps de texte d'un PDF.
///
/// Chaque bloc de texte est pose par une matrice `1 0 0 1 x y cm` : la
/// valeur `x` donne sa position horizontale sur la page.
List<double> extractPdfOrigins(Uint8List bytes) {
  final raw = latin1.decode(bytes, allowInvalid: true);
  final origins = <double>[];
  final pattern = RegExp('stream\r?\n');
  for (final match in pattern.allMatches(raw)) {
    final start = match.end;
    final end = raw.indexOf('endstream', start);
    if (end < 0) {
      continue;
    }
    final payload = latin1.encode(raw.substring(start, end));
    final stream = _inflate(payload);
    final originsPattern = RegExp(r'1 0 0 1 (-?[\d.]+) (-?[\d.]+) cm');
    for (final origin in originsPattern.allMatches(stream)) {
      final value = double.tryParse(origin.group(1)!);
      if (value != null) {
        origins.add(value);
      }
    }
  }
  return origins;
}

/// Dimensions de la page (MediaBox) d'un PDF, en points.
List<double>? extractMediaBox(Uint8List bytes) {
  final raw = latin1.decode(bytes, allowInvalid: true);
  final match = RegExp(
    r'/MediaBox\[0 0 (-?[\d.]+) (-?[\d.]+)\]',
  ).firstMatch(raw);
  if (match == null) {
    return null;
  }
  return <double>[double.parse(match.group(1)!), double.parse(match.group(2)!)];
}
