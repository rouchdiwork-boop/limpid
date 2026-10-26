import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';

/// Texte contenu dans les flux de contenu d'un PDF.
///
/// Les flux sont compresses (Flate) : ils sont decompresses a la volee, puis
/// les chaines de texte (`[(...)]TJ` ou `[<...>]TJ`) sont concatenees.
///
/// Les polices embarquees sont ecrites en `/Identity-H` : leurs chaines sont
/// hexadecimales et chaque code est un index de glyphe. La table
/// `/ToUnicode` de la police permet de le relire comme du texte.
String extractPdfText(Uint8List bytes) {
  final raw = latin1.decode(bytes, allowInvalid: true);
  final decoders = _fontDecoders(raw);
  final builder = StringBuffer();
  for (final stream in extractPdfStreams(bytes)) {
    builder.write(_extractStrings(stream, decoders));
  }
  return builder.toString();
}

/// Les flux de contenu d'un PDF, decompresses.
///
/// Les flux qui ne sont pas compresses (les polices, les images) sont
/// renvoyes vides : ils ne portent pas de texte.
List<String> extractPdfStreams(Uint8List bytes) {
  final raw = latin1.decode(bytes, allowInvalid: true);
  final streams = <String>[];
  final pattern = RegExp('stream\r?\n');
  for (final match in pattern.allMatches(raw)) {
    final start = match.end;
    final end = raw.indexOf('endstream', start);
    if (end < 0) {
      continue;
    }
    final payload = latin1.encode(raw.substring(start, end));
    streams.add(_inflate(payload));
  }
  return streams;
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

/// Les tables de conversion glyphe -> Unicode, par nom de police.
///
/// Chaque police embarquee declare sa table `/ToUnicode` : elle relie les
/// codes ecrits dans le flux de contenu aux caracteres du texte.
Map<String, Map<int, int>> _fontDecoders(String raw) {
  final objects = _objects(raw);
  final decoders = <String, Map<int, int>>{};
  for (final body in objects.values) {
    if (!RegExp(r'/Subtype\s*/Type0').hasMatch(body)) {
      continue;
    }
    final name = RegExp(r'/Name\s*/(\w+)').firstMatch(body);
    final reference = RegExp(r'/ToUnicode\s+(\d+)\s+0\s+R').firstMatch(body);
    if (name == null || reference == null) {
      continue;
    }
    final table = objects[int.parse(reference.group(1)!)];
    if (table == null) {
      continue;
    }
    decoders[name.group(1)!] = _bfcharTable(_streamText(table));
  }
  return decoders;
}

/// Le texte decompresse d'un flux de contenu d'objet.
String _streamText(String body) {
  final match = RegExp('stream\r?\n').firstMatch(body);
  if (match == null) {
    return '';
  }
  final start = match.end;
  final end = body.indexOf('endstream', start);
  if (end < 0) {
    return '';
  }
  return _inflate(latin1.encode(body.substring(start, end)));
}

/// Les corps des objets d'un PDF, indexes par leur numero.
Map<int, String> _objects(String raw) {
  final objects = <int, String>{};
  for (final match in RegExp(r'(?:^|[\r\n])(\d+) 0 obj').allMatches(raw)) {
    final start = match.end;
    final end = raw.indexOf('endobj', start);
    if (end < 0) {
      continue;
    }
    objects[int.parse(match.group(1)!)] = raw.substring(start, end);
  }
  return objects;
}

/// La table `beginbfchar` d'une table `/ToUnicode`.
Map<int, int> _bfcharTable(String body) {
  final table = <int, int>{};
  final section = RegExp(
    r'beginbfchar(.*?)endbfchar',
    dotAll: true,
  ).firstMatch(body);
  if (section == null) {
    return table;
  }
  final entries = RegExp(
    r'<([0-9A-Fa-f]{4})>\s*<([0-9A-Fa-f]{4,})>',
  ).allMatches(section.group(1)!);
  for (final entry in entries) {
    final code = int.tryParse(entry.group(1)!, radix: 16);
    final unicode = int.tryParse(entry.group(2)!, radix: 16);
    if (code != null && unicode != null) {
      table[code] = unicode;
    }
  }
  return table;
}

/// Concatene les chaines de texte d'un flux de contenu PDF.
String _extractStrings(String stream, Map<String, Map<int, int>> decoders) {
  final builder = StringBuffer();
  final pattern = RegExp(
    r'/(\w+)\s+[\d.]+\s+Tf'
    r'|\[\(((?:\\.|[^\\()])*)\)\]TJ'
    r'|\[<([0-9A-Fa-f]*)>\]TJ'
    r'|\[([0-9A-Fa-f]*)\]TJ',
  );
  Map<int, int>? current;
  for (final match in pattern.allMatches(stream)) {
    if (match.group(1) != null) {
      current = decoders[match.group(1)!];
      continue;
    }
    if (match.group(2) != null) {
      builder.write(_unescape(match.group(2)!));
      builder.write(' ');
      continue;
    }
    if (match.group(3) != null) {
      // La police embarquee est une police CID : le texte est ecrit en
      // hexadecimal, deux octets par glyphe, et la table `/ToUnicode` de
      // la police le relit.
      builder.write(_decodeHex(match.group(3)!, current));
      builder.write(' ');
      continue;
    }
    builder.write(_decodeHex(match.group(4)!, current));
    builder.write(' ');
  }
  return builder.toString();
}

/// Relit une chaine hexadecimale d'une police `/Identity-H`.
String _decodeHex(String hex, Map<int, int>? decoder) {
  if (decoder == null) {
    return '';
  }
  final builder = StringBuffer();
  for (var index = 0; index + 4 <= hex.length; index += 4) {
    final code = int.tryParse(hex.substring(index, index + 4), radix: 16);
    if (code == null) {
      continue;
    }
    final unicode = decoder[code];
    if (unicode != null) {
      builder.writeCharCode(unicode);
    }
  }
  return builder.toString();
}

/// Rend lisible une chaine litterale d'un PDF.
String _unescape(String value) {
  return value.replaceAllMapped(RegExp(r'\\(.)'), (match) {
    final escaped = match.group(1) ?? '';
    return switch (escaped) {
      'n' => '\n',
      'r' => '\r',
      't' => '\t',
      'b' => '\b',
      'f' => '\f',
      _ => escaped,
    };
  });
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
