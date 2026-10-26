import 'dart:convert';
import 'dart:typed_data';

import '../model/export_block.dart';
import '../model/export_book.dart';
import '../model/export_options.dart';
import '../util/file_name.dart';
import 'markdown_escaper.dart';
import 'markdown_front_matter.dart';

/// Generateur Markdown.
///
/// Produit un document CommonMark avec un bloc YAML de metadonnees en tete.
/// Les notes de bas de page sont numerotees globalement et definies en fin de
/// document.
class MarkdownWriter {
  /// Cree un generateur Markdown.
  const MarkdownWriter();

  /// Serialise le livre et renvoie les octets du fichier.
  Future<Uint8List> write(ExportBook book, ExportOptions options) async {
    final content = render(book, options);
    return Uint8List.fromList(utf8.encode(content));
  }

  /// Serialise le livre et renvoie le texte Markdown.
  String render(ExportBook book, ExportOptions options) {
    final output = _MarkdownBuffer();
    output.write(MarkdownFrontMatter.render(book));

    var footnoteIndex = 0;
    final definitions = <String>[];

    for (var index = 0; index < book.chapters.length; index++) {
      final chapter = book.chapters[index];
      output.ensureBlankLine();
      output.write('# ${MarkdownEscaper.inline(chapter.title)}\n\n');
      output.write(
        _renderBlocks(chapter.blocks, definitions, () {
          footnoteIndex++;
          return footnoteIndex;
        }),
      );
    }

    if (definitions.isNotEmpty) {
      output.ensureBlankLine();
      for (final definition in definitions) {
        output.write(definition);
      }
    }

    return output.toString();
  }

  String _renderBlocks(
    List<ExportBlock> blocks,
    List<String> definitions,
    int Function() nextFootnote,
  ) {
    final output = _MarkdownBuffer();
    for (final block in blocks) {
      switch (block.type) {
        case ExportBlockType.paragraph:
          output.write(_paragraph(block, definitions, nextFootnote));
        case ExportBlockType.heading1:
          output.ensureBlankLine();
          output.write('# ${MarkdownEscaper.inline(block.text)}\n\n');
        case ExportBlockType.heading2:
          output.ensureBlankLine();
          output.write('## ${MarkdownEscaper.inline(block.text)}\n\n');
        case ExportBlockType.heading3:
          output.ensureBlankLine();
          output.write('### ${MarkdownEscaper.inline(block.text)}\n\n');
        case ExportBlockType.listItem:
          output.write(_listItem(block));
        case ExportBlockType.quote:
          output.ensureBlankLine();
          output.write(_quote(block));
        case ExportBlockType.code:
          output.ensureBlankLine();
          output.write(_code(block));
        case ExportBlockType.image:
          output.ensureBlankLine();
          output.write(_image(block));
        case ExportBlockType.pageBreak:
          output.ensureBlankLine();
          output.write('<!-- saut de page -->\n\n');
        case ExportBlockType.footnote:
          final number = nextFootnote();
          definitions.add(
            '[^$number]: ${MarkdownEscaper.inline(block.text)}\n',
          );
      }
    }
    return output.toString();
  }

  String _paragraph(
    ExportBlock block,
    List<String> definitions,
    int Function() nextFootnote,
  ) {
    final output = _MarkdownBuffer();
    output.write(MarkdownEscaper.block(block.text));
    for (final note in block.footnotes) {
      final number = nextFootnote();
      output.write('[^$number]');
      definitions.add('[^$number]: ${MarkdownEscaper.inline(note)}\n');
    }
    output.write('\n\n');
    return output.toString();
  }

  String _listItem(ExportBlock block) {
    final depth = (block.level ?? 1).clamp(1, 6);
    final indent = '  ' * (depth - 1);
    return '$indent- ${MarkdownEscaper.inline(block.text)}\n';
  }

  String _quote(ExportBlock block) {
    final lines = MarkdownEscaper.block(block.text).split('\n');
    final quoted = lines.map((line) => '> $line').join('\n');
    return '$quoted\n\n';
  }

  String _code(ExportBlock block) {
    final language = block.language;
    const fence = '```';
    return '$fence${language ?? ''}\n${block.text}\n$fence\n\n';
  }

  String _image(ExportBlock block) {
    final alt = MarkdownEscaper.inline(block.text);
    final source =
        block.href ??
        (block.image?.fileName ?? 'image${block.image?.extension ?? ''}');
    return '![$alt]($source)\n\n';
  }

  /// Nom de fichier recommande pour l'export Markdown.
  static String fileNameFor(ExportBook book) =>
      FileNames.forBook(book.title, 'md');

  /// Type MIME du fichier produit.
  static const String mimeType = 'text/markdown; charset=utf-8';
}

/// Tampon Markdown qui garantit la separation des blocs par une ligne vide.
class _MarkdownBuffer {
  final StringBuffer _buffer = StringBuffer();
  bool _endsWithBlankLine = true;

  /// Ecrit du contenu.
  void write(String value) {
    _buffer.write(value);
    _endsWithBlankLine = value.endsWith('\n\n');
  }

  /// Ajoute une ligne vide si necessaire.
  void ensureBlankLine() {
    if (_endsWithBlankLine) {
      return;
    }
    _buffer.write('\n');
    _endsWithBlankLine = true;
  }

  /// Contenu accumule.
  @override
  String toString() => _buffer.toString();
}
