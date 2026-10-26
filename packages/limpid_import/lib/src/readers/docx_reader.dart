import 'dart:convert';
import 'dart:typed_data';

import 'package:xml/xml.dart';

import '../model/import_block.dart';
import '../model/import_exception.dart';
import '../model/import_format.dart';
import '../model/import_request.dart';
import '../model/import_skip.dart';
import 'chapter_builder.dart';
import 'manuscript_reader.dart';
import 'ooxml_text.dart';
import 'parsed_document.dart';
import 'xml_helpers.dart';
import 'zip_package.dart';

/// Le lecteur de document Word (DOCX).
///
/// Le paquet OOXML est lu dans `word/document.xml`. Les styles de titre
/// (`w:pStyle`) donnent le niveau du chapitre ; le texte des runs (`w:t`)
/// donne les blocs. Les images, les notes et les commentaires du fichier
/// source ne sont pas importes : ils sont annonces.
final class DocxReader implements ManuscriptReader {
  /// Cree un lecteur DOCX.
  const DocxReader();

  @override
  ImportFormat get format => ImportFormat.docx;

  @override
  ParsedDocument read(ImportRequest request) {
    final ZipPackage package = ZipPackage.open(request.bytes);
    final Uint8List? body = package.file('word/document.xml');
    if (body == null) {
      throw const ImportException(
        ImportErrorCodes.unreadable,
        'Le document Word ne contient pas de corps lisible.',
      );
    }

    final _DocxNumbering numbering = _DocxNumbering.read(
      package.file('word/numbering.xml'),
    );
    final XmlDocument document = _parse(body);
    final XmlElement? content = childOf(document.rootElement, 'body');
    if (content == null) {
      throw const ImportException(
        ImportErrorCodes.unreadable,
        'Le document Word ne contient pas de corps lisible.',
      );
    }

    final ChapterBuilder builder = ChapterBuilder(
      defaultTitle: request.baseName,
    );
    for (final XmlElement element in content.children.whereType<XmlElement>()) {
      switch (element.name.local) {
        case 'p':
          _readParagraph(element, builder, numbering);
        case 'tbl':
          _readTable(element, builder);
        case 'sdt':
          final XmlElement? sdtContent = childOf(element, 'sdtContent');
          if (sdtContent == null) break;
          for (final XmlElement child
              in sdtContent.children.whereType<XmlElement>()) {
            if (child.name.local == 'p') {
              _readParagraph(child, builder, numbering);
            }
          }
      }
    }

    return builder.build(
      title: _titleOf(package),
      skipped: _skippedOf(package, content),
    );
  }

  static XmlDocument _parse(Uint8List bytes) {
    try {
      return XmlDocument.parse(utf8.decode(bytes));
    } on XmlException catch (error) {
      throw ImportException(
        ImportErrorCodes.unreadable,
        'Le document Word est illisible.',
        cause: error,
      );
    }
  }

  void _readParagraph(
    XmlElement paragraph,
    ChapterBuilder builder,
    _DocxNumbering numbering,
  ) {
    final XmlElement? properties = childOf(paragraph, 'pPr');
    String? styleId;
    String? numId;
    int? outline;
    var pageBreakBefore = false;
    if (properties != null) {
      final XmlElement? style = childOf(properties, 'pStyle');
      styleId = style == null ? null : attributeOf(style, 'val');
      final XmlElement? numProperties = childOf(properties, 'numPr');
      if (numProperties != null) {
        final XmlElement? num = childOf(numProperties, 'numId');
        numId = num == null ? null : attributeOf(num, 'val');
      }
      final XmlElement? outlineElement = childOf(properties, 'outlineLvl');
      final String? raw = outlineElement == null
          ? null
          : attributeOf(outlineElement, 'val');
      if (raw != null) outline = int.tryParse(raw);
      pageBreakBefore = childOf(properties, 'pageBreakBefore') != null;
    }

    final String text = ooxmlTextOf(paragraph).trim();
    final bool pageBreak = pageBreakBefore || _hasPageBreak(paragraph);
    final int? heading =
        _headingLevelOf(styleId) ??
        (outline != null && outline >= 0 ? outline + 1 : null);

    if (pageBreak) builder.breakScene();

    if (heading != null) {
      builder.openChapter(text, level: heading);
      return;
    }
    if (text.isEmpty) return;
    if (_isCodeStyle(styleId)) {
      builder.addBlock(
        ImportedBlock(
          type: ImportedBlockType.code,
          text: text,
          language: _languageOf(styleId),
        ),
      );
      return;
    }
    if (numId != null || _isListStyle(styleId)) {
      builder.addBlock(
        ImportedBlock(
          type: ImportedBlockType.listItem,
          text: text,
          level: 1,
          isOrdered: numbering.isOrdered(numId),
        ),
      );
      return;
    }
    builder.addBlock(
      ImportedBlock(type: ImportedBlockType.paragraph, text: text),
    );
  }

  void _readTable(XmlElement table, ChapterBuilder builder) {
    for (final XmlElement row in table.children.whereType<XmlElement>()) {
      if (row.name.local != 'tr') continue;
      for (final XmlElement cell in row.children.whereType<XmlElement>()) {
        if (cell.name.local != 'tc') continue;
        for (final XmlElement paragraph
            in cell.children.whereType<XmlElement>()) {
          if (paragraph.name.local != 'p') continue;
          final String text = ooxmlTextOf(paragraph).trim();
          if (text.isEmpty) continue;
          builder.addBlock(
            ImportedBlock(type: ImportedBlockType.paragraph, text: text),
          );
        }
      }
    }
  }

  /// Le niveau de titre que porte le style [styleId], `null` quand le style
  /// n'est pas un titre.
  ///
  /// Word ecrit `Heading1` en anglais et `Titre1` en francais : les deux
  /// noms sont lus.
  static int? _headingLevelOf(String? styleId) {
    if (styleId == null) return null;
    final String normalized = _normalize(styleId);
    final RegExpMatch? match = RegExp(
      r'^(?:heading|titre)(\d)$',
    ).firstMatch(normalized);
    if (match != null) {
      final int level = int.parse(match.group(1)!);
      return level > 3 ? 3 : level;
    }
    if (normalized == 'title') return 1;
    if (normalized == 'subtitle') return 2;
    return null;
  }

  static bool _isListStyle(String? styleId) =>
      styleId != null && _normalize(styleId) == 'listparagraph';

  static bool _isCodeStyle(String? styleId) {
    if (styleId == null) return false;
    final String normalized = _normalize(styleId);
    return normalized.startsWith('code') ||
        normalized.startsWith('sourcecode') ||
        normalized == 'htmlpreformatted' ||
        normalized == 'preformattedtext' ||
        normalized == 'plaintext';
  }

  /// Le langage annonce par le style [styleId], `null` quand il n'y en a
  /// pas.
  static String? _languageOf(String? styleId) {
    if (styleId == null) return null;
    final RegExpMatch? match = RegExp(
      r'^(?:code|sourcecode)[-_ ]?([a-z0-9+#]+)$',
      caseSensitive: false,
    ).firstMatch(styleId.replaceAll(' ', ''));
    if (match == null) return null;
    final String language = match.group(1)!.toLowerCase();
    return language.isEmpty ? null : language;
  }

  static String _normalize(String styleId) =>
      styleId.toLowerCase().replaceAll(RegExp(r'[\s\-_]'), '');

  static bool _hasPageBreak(XmlElement paragraph) {
    for (final XmlElement element
        in paragraph.descendants.whereType<XmlElement>()) {
      if (element.name.local != 'br') continue;
      if (attributeOf(element, 'type') == 'page') return true;
    }
    return false;
  }

  /// Le titre du document, lu dans `docProps/core.xml`.
  static String? _titleOf(ZipPackage package) {
    final Uint8List? core = package.file('docProps/core.xml');
    if (core == null) return null;
    try {
      final XmlDocument document = XmlDocument.parse(utf8.decode(core));
      final XmlElement? title = descendantNamed(document.rootElement, 'title');
      final String? value = title?.innerText.trim();
      return value == null || value.isEmpty ? null : value;
    } on XmlException {
      return null;
    }
  }

  /// Les contenus que le lecteur a laisses de cote.
  static List<ImportSkip> _skippedOf(ZipPackage package, XmlElement body) {
    final List<ImportSkip> skipped = <ImportSkip>[];

    final int images = package.entriesUnder('word/media/').length;
    if (images > 0) {
      skipped.add(ImportSkip(reason: 'images', count: images));
    }

    var notes = 0;
    var comments = 0;
    for (final XmlElement element in body.descendants.whereType<XmlElement>()) {
      switch (element.name.local) {
        case 'footnoteReference':
        case 'endnoteReference':
          notes++;
        case 'commentReference':
          comments++;
      }
    }
    if (notes > 0) skipped.add(ImportSkip(reason: 'notes', count: notes));
    if (comments > 0) {
      skipped.add(ImportSkip(reason: 'comments', count: comments));
    }
    return skipped;
  }
}

/// La numerotation des listes d'un document Word.
///
/// `word/numbering.xml` dit, pour chaque liste, si ses elements sont
/// ordonnes ou non. L'import ne devine pas : il lit.
final class _DocxNumbering {
  const _DocxNumbering(this._orderedByNumId);

  final Map<String, bool> _orderedByNumId;

  /// Whether the list numbered [numId] is ordered.
  bool isOrdered(String? numId) {
    if (numId == null) return false;
    return _orderedByNumId[numId] ?? false;
  }

  /// Lit la numerotation du paquet, quand le document en porte une.
  static _DocxNumbering read(Uint8List? bytes) {
    if (bytes == null) return const _DocxNumbering(<String, bool>{});
    try {
      final XmlDocument document = XmlDocument.parse(utf8.decode(bytes));
      return _DocxNumbering(_read(document.rootElement));
    } on XmlException {
      return const _DocxNumbering(<String, bool>{});
    }
  }

  static Map<String, bool> _read(XmlElement root) {
    final Map<String, String> abstractByNumId = <String, String>{};
    final Map<String, bool> orderedByAbstract = <String, bool>{};

    for (final XmlElement element in root.children.whereType<XmlElement>()) {
      if (element.name.local != 'abstractNum') continue;
      final String? id = attributeOf(element, 'abstractNumId');
      if (id == null) continue;
      orderedByAbstract[id] = _isOrderedFormat(element);
    }
    for (final XmlElement element in root.children.whereType<XmlElement>()) {
      if (element.name.local != 'num') continue;
      final String? numId = attributeOf(element, 'numId');
      final XmlElement? abstract = childOf(element, 'abstractNumId');
      final String? abstractId = abstract == null
          ? null
          : attributeOf(abstract, 'val');
      if (numId == null || abstractId == null) continue;
      abstractByNumId[numId] = abstractId;
    }

    final Map<String, bool> ordered = <String, bool>{};
    for (final MapEntry<String, String> entry in abstractByNumId.entries) {
      ordered[entry.key] = orderedByAbstract[entry.value] ?? false;
    }
    return ordered;
  }

  static bool _isOrderedFormat(XmlElement abstractNum) {
    final XmlElement? level = childOf(abstractNum, 'lvl');
    final XmlElement? format = level == null ? null : childOf(level, 'numFmt');
    final String? value = format == null ? null : attributeOf(format, 'val');
    if (value == null) return false;
    return value != 'bullet' && value != 'none';
  }
}
