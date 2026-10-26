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
import 'parsed_document.dart';
import 'xml_helpers.dart';
import 'zip_package.dart';

/// Le lecteur de livre electronique EPUB.
///
/// Le paquet EPUB est lu par le chemin complet du document OPF, donne par
/// `META-INF/container.xml`. La spine donne l'ordre des documents, et le
/// titre de chaque document est un chapitre. Les titres internes au
/// document separent ses scenes.
final class EpubReader implements ManuscriptReader {
  /// Cree un lecteur EPUB.
  const EpubReader();

  /// Le type MIME des documents XHTML d'un EPUB.
  static const String xhtmlMediaType = 'application/xhtml+xml';

  @override
  ImportFormat get format => ImportFormat.epub;

  @override
  ParsedDocument read(ImportRequest request) {
    final ZipPackage package = ZipPackage.open(request.bytes);
    final String? opfPath = _opfPathOf(package);
    if (opfPath == null) {
      throw const ImportException(
        ImportErrorCodes.unreadable,
        'Le livre EPUB ne contient pas de document de description.',
      );
    }
    final Uint8List? opfBytes = package.file(opfPath);
    if (opfBytes == null) {
      throw const ImportException(
        ImportErrorCodes.unreadable,
        'Le livre EPUB ne contient pas de document de description.',
      );
    }

    final XmlDocument opf = _parse(opfBytes);
    final _EpubManifest manifest = _EpubManifest.read(opf.rootElement);
    final String base = _directoryOf(opfPath);

    final ChapterBuilder builder = ChapterBuilder(
      defaultTitle: request.baseName,
    );
    final _EpubCounter counter = _EpubCounter();
    var order = 0;

    for (final String idref in manifest.spine) {
      final _EpubItem? item = manifest.itemOf(idref);
      if (item == null) continue;
      if (item.mediaType != xhtmlMediaType && item.mediaType != 'text/html') {
        continue;
      }
      if (item.isNavigation) continue;
      final Uint8List? bytes = package.file(_resolve(base, item.href));
      if (bytes == null) continue;

      final XmlDocument document = _parse(bytes);
      final _EpubContent content = _EpubContent.read(document.rootElement);
      order++;
      builder.openChapter(
        content.title.isEmpty ? 'Chapitre $order' : content.title,
        level: content.level,
      );
      for (final _EpubSection section in content.sections) {
        builder.openScene(section.title);
        for (final ImportedBlock block in section.blocks) {
          builder.addBlock(block);
        }
      }
      counter.images += content.images;
      counter.notes += content.notes;
    }

    return builder.build(
      title: manifest.title ?? request.baseName,
      skipped: _skippedOf(counter),
    );
  }

  static XmlDocument _parse(Uint8List bytes) {
    try {
      return XmlDocument.parse(utf8.decode(bytes));
    } on XmlException catch (error) {
      throw ImportException(
        ImportErrorCodes.unreadable,
        'Le livre EPUB est illisible.',
        cause: error,
      );
    }
  }

  /// Le chemin du document OPF, lu dans `META-INF/container.xml`.
  static String? _opfPathOf(ZipPackage package) {
    final Uint8List? container = package.file('META-INF/container.xml');
    if (container == null) return null;
    try {
      final XmlDocument document = XmlDocument.parse(utf8.decode(container));
      for (final XmlElement rootfile
          in document.rootElement.descendants.whereType<XmlElement>()) {
        if (rootfile.name.local != 'rootfile') continue;
        final String? path = attributeOf(rootfile, 'full-path');
        if (path != null && path.isNotEmpty) return path;
      }
    } on XmlException {
      return null;
    }
    return null;
  }

  /// Le repertoire qui contient [path].
  static String _directoryOf(String path) {
    final int slash = path.lastIndexOf('/');
    return slash < 0 ? '' : path.substring(0, slash + 1);
  }

  /// Le chemin de [href] relatif au repertoire [base].
  static String _resolve(String base, String href) {
    final String decoded = _decode(href);
    if (decoded.startsWith('/')) return decoded.substring(1);
    final List<String> parts = base
        .split('/')
        .where((String segment) => segment.isNotEmpty)
        .toList();
    for (final String segment in decoded.split('/')) {
      if (segment == '.' || segment.isEmpty) continue;
      if (segment == '..') {
        if (parts.isNotEmpty) parts.removeLast();
        continue;
      }
      parts.add(segment);
    }
    return parts.join('/');
  }

  static String _decode(String value) {
    final StringBuffer buffer = StringBuffer();
    for (var index = 0; index < value.length; index++) {
      if (value[index] == '%' && index + 2 < value.length) {
        final int? code = int.tryParse(
          value.substring(index + 1, index + 3),
          radix: 16,
        );
        if (code != null) {
          buffer.writeCharCode(code);
          index += 2;
          continue;
        }
      }
      buffer.write(value[index]);
    }
    return buffer.toString();
  }

  static List<ImportSkip> _skippedOf(_EpubCounter counter) {
    final List<ImportSkip> skipped = <ImportSkip>[];
    if (counter.images > 0) {
      skipped.add(ImportSkip(reason: 'images', count: counter.images));
    }
    if (counter.notes > 0) {
      skipped.add(ImportSkip(reason: 'notes', count: counter.notes));
    }
    return skipped;
  }
}

/// Le compte des contenus laisses de cote.
final class _EpubCounter {
  int images = 0;
  int notes = 0;
}

/// Une entree du manifeste d'un EPUB.
final class _EpubItem {
  const _EpubItem({
    required this.id,
    required this.href,
    required this.mediaType,
    required this.isNavigation,
  });

  /// L'identifiant de l'entree.
  final String id;

  /// Le chemin de la ressource, relatif au document OPF.
  final String href;

  /// Le type MIME de la ressource.
  final String mediaType;

  /// Whether the entry is the navigation document of the book.
  final bool isNavigation;
}

/// Le manifeste et la spine d'un EPUB.
final class _EpubManifest {
  const _EpubManifest({required this.items, required this.spine, this.title});

  /// Les entrees du manifeste, indexees par leur identifiant.
  final Map<String, _EpubItem> items;

  /// Les identifiants de la spine, dans l'ordre de lecture.
  final List<String> spine;

  /// Le titre du livre, `null` quand le livre n'en porte pas.
  final String? title;

  /// L'entree d'identifiant [id], `null` quand elle n'existe pas.
  _EpubItem? itemOf(String id) => items[id];

  /// Lit le manifeste et la spine de [root].
  static _EpubManifest read(XmlElement root) {
    final Map<String, _EpubItem> items = <String, _EpubItem>{};
    final List<String> spine = <String>[];
    String? title;

    for (final XmlElement element in root.descendants.whereType<XmlElement>()) {
      switch (element.name.local) {
        case 'title':
          if (title == null) {
            final String value = element.innerText.trim();
            if (value.isNotEmpty) title = value;
          }
        case 'item':
          final String? id = attributeOf(element, 'id');
          final String? href = attributeOf(element, 'href');
          if (id == null || href == null) continue;
          final String properties = attributeOf(element, 'properties') ?? '';
          items[id] = _EpubItem(
            id: id,
            href: href,
            mediaType: attributeOf(element, 'media-type') ?? '',
            isNavigation: properties.split(' ').contains('nav'),
          );
        case 'itemref':
          final String? idref = attributeOf(element, 'idref');
          if (idref != null) spine.add(idref);
      }
    }

    return _EpubManifest(items: items, spine: spine, title: title);
  }
}

/// Une section d'un document XHTML d'EPUB.
final class _EpubSection {
  const _EpubSection({required this.title, required this.blocks});

  /// Le titre de la section.
  final String title;

  /// Les blocs de la section.
  final List<ImportedBlock> blocks;
}

/// Le contenu lu d'un document XHTML.
final class _EpubContent {
  const _EpubContent({
    required this.title,
    required this.level,
    required this.sections,
    required this.images,
    required this.notes,
  });

  /// Le titre du document.
  final String title;

  /// Le niveau du premier titre du document.
  final int level;

  /// Les sections du document.
  final List<_EpubSection> sections;

  /// Le nombre d'images laissees de cote.
  final int images;

  /// Le nombre de notes laissees de cote.
  final int notes;

  /// Lit le contenu de [root].
  static _EpubContent read(XmlElement root) {
    final List<_EpubSection> sections = <_EpubSection>[];
    final List<ImportedBlock> blocks = <ImportedBlock>[];
    String sectionTitle = '';
    var level = 1;
    var images = 0;
    var notes = 0;
    var seenHeading = false;

    void closeSection() {
      if (blocks.isEmpty && sectionTitle.isEmpty) return;
      sections.add(
        _EpubSection(
          title: sectionTitle,
          blocks: List<ImportedBlock>.unmodifiable(blocks),
        ),
      );
      blocks.clear();
    }

    void walk(XmlElement parent) {
      for (final XmlElement element
          in parent.children.whereType<XmlElement>()) {
        final String name = element.name.local;
        switch (name) {
          case 'h1':
          case 'h2':
          case 'h3':
          case 'h4':
          case 'h5':
          case 'h6':
            closeSection();
            sectionTitle = _textOf(element);
            if (!seenHeading) {
              seenHeading = true;
              final int headingLevel = int.parse(name.substring(1));
              level = headingLevel > 3 ? 3 : headingLevel;
            }
          case 'p':
            final String text = _textOf(element);
            if (text.isEmpty) continue;
            blocks.add(
              ImportedBlock(type: ImportedBlockType.paragraph, text: text),
            );
          case 'ul':
          case 'ol':
            for (final XmlElement item in childrenNamed(element, 'li')) {
              final String text = _textOf(item);
              if (text.isEmpty) continue;
              blocks.add(
                ImportedBlock(
                  type: ImportedBlockType.listItem,
                  text: text,
                  level: 1,
                  isOrdered: name == 'ol',
                ),
              );
            }
          case 'blockquote':
            final String text = _textOf(element);
            if (text.isEmpty) continue;
            blocks.add(
              ImportedBlock(type: ImportedBlockType.quote, text: text),
            );
          case 'pre':
            final String text = _textOf(element);
            if (text.isEmpty) continue;
            blocks.add(
              ImportedBlock(
                type: ImportedBlockType.code,
                text: text,
                language: _languageOf(element),
              ),
            );
          case 'hr':
            closeSection();
            sectionTitle = '';
          case 'img':
            images++;
          case 'aside':
            final String type = attributeOf(element, 'type') ?? '';
            if (type.contains('footnote') || type.contains('endnote')) {
              notes++;
              continue;
            }
            walk(element);
          case 'table':
            for (final XmlElement cell
                in element.descendants.whereType<XmlElement>()) {
              if (cell.name.local != 'td') continue;
              final String text = _textOf(cell);
              if (text.isEmpty) continue;
              blocks.add(
                ImportedBlock(type: ImportedBlockType.paragraph, text: text),
              );
            }
          case 'head':
          case 'script':
          case 'style':
          case 'title':
            continue;
          default:
            walk(element);
        }
      }
    }

    final XmlElement? head = childOf(root, 'head');
    final XmlElement? body = childOf(root, 'body');
    String title = '';
    if (head != null) {
      final XmlElement? titleElement = childOf(head, 'title');
      title = titleElement == null ? '' : _textOf(titleElement);
    }
    if (body != null) walk(body);
    closeSection();

    return _EpubContent(
      title: title,
      level: level,
      sections: sections,
      images: images,
      notes: notes,
    );
  }

  /// Le texte d'un element, les espaces being reduced.
  static String _textOf(XmlElement element) {
    return element.innerText.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  /// The language declared by the class of [element].
  static String? _languageOf(XmlElement element) {
    final String? classes = attributeOf(element, 'class');
    if (classes == null) return null;
    for (final String name in classes.split(' ')) {
      if (name.startsWith('language-')) {
        final String language = name.substring('language-'.length);
        if (language.isNotEmpty) return language;
      }
    }
    return null;
  }
}
