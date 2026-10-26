import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';

/// La structure d'un paquet EPUB, lue depuis les octets produits.
///
/// Le paquet EPUB est un ZIP : la classe en lit le central directory et le
/// contenu des entrees. Elle sert au controle de soumission, qui verifie
/// dans le fichier produit ce qu'Amazon verifie lui-meme sur le dossier
/// depose.
final class EpubPackage {
  /// Cree un paquet a partir des entrees lues.
  EpubPackage._(this._entries);

  /// Lit le paquet [bytes].
  ///
  /// Renvoie `null` quand les octets ne forment pas un ZIP lisible : le
  /// fichier produit est alors inexploitable, ce que le controle signale.
  static EpubPackage? read(Uint8List bytes) {
    try {
      final Archive archive = ZipDecoder().decodeBytes(bytes);
      return EpubPackage._(<String, Uint8List>{
        for (final ArchiveFile file in archive.files)
          if (file.isFile) file.name: file.readBytes() ?? Uint8List(0),
      });
    } on Object {
      return null;
    }
  }

  final Map<String, Uint8List> _entries;

  /// Les noms des entrees du paquet, dans l'ordre du central directory.
  List<String> get entryNames => List<String>.unmodifiable(_entries.keys);

  /// Le contenu textuel de l'entree [name], `null` quand elle est absente.
  String? textOf(String name) {
    final Uint8List? bytes = _entries[name];
    if (bytes == null) return null;
    try {
      return utf8.decode(bytes);
    } on FormatException {
      return null;
    }
  }

  /// Le nom de l'entree qui porte le document de navigation.
  String? get navigationEntryName => _entryNameEndingWith('nav.xhtml');

  /// Le document de navigation du paquet, `null` quand il est absent.
  String? get navigationDocument {
    final String? name = navigationEntryName;
    if (name == null) return null;
    return textOf(name);
  }

  /// Le document de description du paquet (le paquet OPF).
  String? get packageDocument {
    final String? name = _entryNameEndingWith('.opf');
    if (name == null) return null;
    return textOf(name);
  }

  /// Vrai quand le paquet porte une table des matieres EPUB 3.
  bool get hasTableOfContents =>
      navigationDocument?.contains('epub:type="toc"') ?? false;

  /// Vrai quand le manifeste du paquet declare le document de navigation.
  bool get declaresNavigation =>
      packageDocument?.contains('properties="nav"') ?? false;

  /// Le nombre de documents du corps du livre, la navigation exclue.
  int get contentDocumentCount {
    final String? navigation = navigationEntryName;
    return _entries.keys
        .where((String name) => name.endsWith('.xhtml'))
        .where((String name) => name != navigation)
        .length;
  }

  /// Le nombre de documents que la spine du paquet reference.
  int get spineItemCount {
    final String? document = packageDocument;
    if (document == null) return 0;
    return '<itemref'.allMatches(document).length;
  }

  /// Vrai quand le paquet porte l'entree `mimetype` imposee par la
  /// specification EPUB 3.
  bool get hasMimeType => _entries.containsKey('mimetype');

  /// Le nom de la premiere entree dont le nom finit par [suffix].
  String? _entryNameEndingWith(String suffix) {
    for (final String name in _entries.keys) {
      if (name.endsWith(suffix)) return name;
    }
    return null;
  }
}
