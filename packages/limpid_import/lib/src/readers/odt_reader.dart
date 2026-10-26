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
import 'odf_text.dart';
import 'parsed_document.dart';
import 'xml_helpers.dart';
import 'zip_package.dart';

/// Le lecteur de document OpenDocument Text (ODT).
///
/// Le paquet ODF est lu dans `content.xml`. Les titres (`text:h`) donnent le
/// niveau du chapitre, grace a `text:outline-level` ou au style de
/// l'element ; les paragraphes (`text:p`) donnent les blocs ; les listes
/// (`text:list`) donnent autant de blocs que d'elements.
final class OdtReader implements ManuscriptReader {
  /// Cree un lecteur ODT.
  const OdtReader();

  @override
  ImportFormat get format => ImportFormat.odt;

  @override
  ParsedDocument read(ImportRequest request) {
    final ZipPackage package = ZipPackage.open(request.bytes);
    final Uint8List? content = package.file('content.xml');
    if (content == null) {
      throw const ImportException(
        ImportErrorCodes.unreadable,
        'Le document OpenDocument ne contient pas de corps lisible.',
      );
    }

    final XmlDocument document = _parse(content);
    final XmlElement? text = descendantNamed(document.rootElement, 'text');
    if (text == null) {
      throw const ImportException(
        ImportErrorCodes.unreadable,
        'Le document OpenDocument ne contient pas de corps lisible.',
      );
    }

    final _OdfStyles styles = _OdfStyles.read(document.rootElement);
    final ChapterBuilder builder = ChapterBuilder(
      defaultTitle: request.baseName,
    );
    final _OdfCounter counter = _OdfCounter();
    _readBody(text, builder, styles, counter);

    return builder.build(
      title: _titleOf(package),
      skipped: _skippedOf(counter),
    );
  }

  static XmlDocument _parse(Uint8List bytes) {
    try {
      return XmlDocument.parse(utf8.decode(bytes));
    } on XmlException catch (error) {
      throw ImportException(
        ImportErrorCodes.unreadable,
        'Le document OpenDocument est illisible.',
        cause: error,
      );
    }
  }

  void _readBody(
    XmlElement parent,
    ChapterBuilder builder,
    _OdfStyles styles,
    _OdfCounter counter,
  ) {
    for (final XmlElement element in parent.children.whereType<XmlElement>()) {
      switch (element.name.local) {
        case 'h':
          final String title = odfTextOf(element).trim();
          builder.openChapter(title, level: styles.outlineLevelOf(element));
        case 'p':
          final String text = odfTextOf(element).trim();
          if (text.isEmpty) break;
          builder.addBlock(
            ImportedBlock(type: ImportedBlockType.paragraph, text: text),
          );
        case 'list':
          _readList(element, builder, styles, counter, 1);
        case 'section':
          _readBody(element, builder, styles, counter);
        case 'soft-page-break':
          builder.breakScene();
        case 'note':
          counter.notes++;
        case 'annotation':
          counter.annotations++;
        case 'frame':
        case 'image':
          counter.images++;
      }
    }
  }

  void _readList(
    XmlElement list,
    ChapterBuilder builder,
    _OdfStyles styles,
    _OdfCounter counter,
    int depth,
  ) {
    final bool ordered = styles.isOrderedList(list);
    for (final XmlElement item in childrenNamed(list, 'list-item')) {
      for (final XmlElement paragraph in childrenNamed(item, 'p')) {
        final String text = odfTextOf(paragraph).trim();
        if (text.isEmpty) continue;
        builder.addBlock(
          ImportedBlock(
            type: ImportedBlockType.listItem,
            text: text,
            level: depth,
            isOrdered: ordered,
          ),
        );
      }
      for (final XmlElement nested in childrenNamed(item, 'list')) {
        _readList(nested, builder, styles, counter, depth + 1);
      }
    }
  }

  /// Le titre du document, lu dans `meta.xml`.
  static String? _titleOf(ZipPackage package) {
    final Uint8List? meta = package.file('meta.xml');
    if (meta == null) return null;
    try {
      final XmlDocument document = XmlDocument.parse(utf8.decode(meta));
      final XmlElement? title = descendantNamed(document.rootElement, 'title');
      final String? value = title?.innerText.trim();
      return value == null || value.isEmpty ? null : value;
    } on XmlException {
      return null;
    }
  }

  static List<ImportSkip> _skippedOf(_OdfCounter counter) {
    final List<ImportSkip> skipped = <ImportSkip>[];
    if (counter.images > 0) {
      skipped.add(ImportSkip(reason: 'images', count: counter.images));
    }
    if (counter.notes > 0) {
      skipped.add(ImportSkip(reason: 'notes', count: counter.notes));
    }
    if (counter.annotations > 0) {
      skipped.add(ImportSkip(reason: 'comments', count: counter.annotations));
    }
    return skipped;
  }
}

/// Le compte des contenus laisses de cote.
final class _OdfCounter {
  int images = 0;
  int notes = 0;
  int annotations = 0;
}

/// Les styles automatiques d'un document ODF.
///
/// Les niveaux de titre et la nature des listes sont portes par les styles :
/// l'import les lit plutot que de les deviner.
final class _OdfStyles {
  const _OdfStyles({
    required this.outlineByStyle,
    required this.orderedByStyle,
  });

  /// Le niveau de plan porte par chaque style de titre.
  final Map<String, int> outlineByStyle;

  /// Les styles qui designent une liste ordonnee.
  final Set<String> orderedByStyle;

  /// Lit les styles automatiques de [root].
  static _OdfStyles read(XmlElement root) {
    final Map<String, int> outline = <String, int>{};
    final Set<String> ordered = <String>{};

    for (final XmlElement container in root.children.whereType<XmlElement>()) {
      if (container.name.local != 'automatic-styles') continue;
      for (final XmlElement style in childrenNamed(container, 'style')) {
        final String? name = attributeOf(style, 'name');
        if (name == null) continue;
        final XmlElement? outlineElement = childOf(style, 'outline-level');
        final String? raw = outlineElement == null
            ? null
            : attributeOf(outlineElement, 'val');
        final int? level = raw == null ? null : int.tryParse(raw);
        if (level != null) outline[name] = level;

        if (childOf(style, 'list-style') == null) continue;
        final XmlElement? listStyle = childOf(style, 'list-style');
        if (listStyle == null) continue;
        if (childOf(listStyle, 'list-level-style-number') != null) {
          ordered.add(name);
        }
      }
    }
    return _OdfStyles(outlineByStyle: outline, orderedByStyle: ordered);
  }

  /// Le niveau du titre porte par [heading].
  int outlineLevelOf(XmlElement heading) {
    final String? raw = attributeOf(heading, 'outline-level');
    final int? direct = raw == null ? null : int.tryParse(raw);
    if (direct != null) return direct > 3 ? 3 : (direct < 1 ? 1 : direct);

    final String? styleName = attributeOf(heading, 'style-name');
    if (styleName != null) {
      final int? level = outlineByStyle[styleName];
      if (level != null) return level > 3 ? 3 : (level < 1 ? 1 : level);
    }
    return 1;
  }

  /// Whether the list [list] is ordered.
  bool isOrderedList(XmlElement list) {
    final String? styleName = attributeOf(list, 'style-name');
    if (styleName != null && orderedByStyle.contains(styleName)) return true;
    for (final XmlElement item in childrenNamed(list, 'list-item')) {
      final String? itemStyle = attributeOf(item, 'style-name');
      if (itemStyle != null && orderedByStyle.contains(itemStyle)) return true;
    }
    return false;
  }
}
