import '../model/import_block.dart';
import '../model/import_format.dart';
import '../model/import_request.dart';
import 'chapter_builder.dart';
import 'manuscript_reader.dart';
import 'parsed_document.dart';
import 'text_decoding.dart';

/// Le lecteur de Markdown.
///
/// Les titres `#`, `##` et `###` ouvrent un chapitre et donnent son
/// niveau ; le corps devient des blocs. Une liste devient **plusieurs**
/// blocs : chaque element est un bloc a part ent, jamais un paragraphe
/// colle. Un bloc de code garde le langage annonce dans son info-string.
final class MarkdownReader implements ManuscriptReader {
  /// Cree un lecteur Markdown.
  const MarkdownReader();

  @override
  ImportFormat get format => ImportFormat.markdown;

  @override
  ParsedDocument read(ImportRequest request) {
    final String text = decodeText(request.bytes);
    final List<String> lines = text.split('\n');
    final _FrontMatter front = _FrontMatter.read(lines);
    final ChapterBuilder builder = ChapterBuilder(
      defaultTitle: request.baseName,
    );

    final List<String> paragraph = <String>[];
    final List<String> quote = <String>[];
    final List<String> code = <String>[];
    String? fence;
    String fenceLanguage = '';

    void flushParagraph() {
      if (paragraph.isEmpty) return;
      final String content = paragraph.join(' ').trim();
      paragraph.clear();
      if (content.isEmpty) return;
      builder.addBlock(
        ImportedBlock(type: ImportedBlockType.paragraph, text: content),
      );
    }

    void flushQuote() {
      if (quote.isEmpty) return;
      final String content = quote.join(' ').trim();
      quote.clear();
      if (content.isEmpty) return;
      builder.addBlock(
        ImportedBlock(type: ImportedBlockType.quote, text: content),
      );
    }

    void flushAll() {
      flushParagraph();
      flushQuote();
    }

    for (var index = front.consumedLines; index < lines.length; index++) {
      final String line = lines[index];

      if (fence != null) {
        if (_closesFence(line, fence)) {
          builder.addBlock(
            ImportedBlock(
              type: ImportedBlockType.code,
              text: code.join('\n'),
              language: fenceLanguage.isEmpty ? null : fenceLanguage,
            ),
          );
          code.clear();
          fence = null;
          fenceLanguage = '';
        } else {
          code.add(line);
        }
        continue;
      }

      final _FenceStart? fenceStart = _FenceStart.of(line);
      if (fenceStart != null) {
        flushAll();
        fence = fenceStart.marker;
        fenceLanguage = fenceStart.language;
        continue;
      }

      final _Heading? heading = _Heading.of(line);
      if (heading != null) {
        flushAll();
        builder.openChapter(heading.text, level: heading.level);
        continue;
      }

      if (_isThematicBreak(line)) {
        flushAll();
        builder.breakScene();
        continue;
      }

      final _ListItem? item = _ListItem.of(line);
      if (item != null) {
        flushAll();
        builder.addBlock(
          ImportedBlock(
            type: ImportedBlockType.listItem,
            text: item.text,
            level: item.level,
            isOrdered: item.isOrdered,
          ),
        );
        continue;
      }

      final _Quote? quoted = _Quote.of(line);
      if (quoted != null) {
        flushParagraph();
        quote.add(quoted.text);
        continue;
      }

      if (line.trim().isEmpty) {
        flushAll();
        continue;
      }

      flushQuote();
      paragraph.add(line.trim());
    }

    // Un fichier peut finir au milieu d'un bloc de code : le bloc est
    // quand meme rendu, il porte ce qu'il a.
    if (fence != null && code.isNotEmpty) {
      builder.addBlock(
        ImportedBlock(
          type: ImportedBlockType.code,
          text: code.join('\n'),
          language: fenceLanguage.isEmpty ? null : fenceLanguage,
        ),
      );
    }
    flushAll();

    return builder.build(title: front.title);
  }
}

/// L'en-tete `---` d'un fichier Markdown.
///
/// L'en-tete peut porter un titre : il est lu, et le reste de l'en-tete
/// est ignore. Un fichier sans en-tete n'est pas affecte.
final class _FrontMatter {
  const _FrontMatter({required this.consumedLines, required this.title});

  /// Le nombre de lignes consommees par l'en-tete.
  final int consumedLines;

  /// Le titre annonce par l'en-tete, `null` quand il n'y en a pas.
  final String? title;

  /// Lit l'en-tete de [lines].
  static _FrontMatter read(List<String> lines) {
    if (lines.isEmpty || lines.first.trim() != '---') {
      return const _FrontMatter(consumedLines: 0, title: null);
    }
    String? title;
    for (var index = 1; index < lines.length; index++) {
      final String line = lines[index].trim();
      if (line == '---') {
        return _FrontMatter(consumedLines: index + 1, title: title);
      }
      if (title != null || !line.startsWith('title:')) continue;
      final String raw = line.substring('title:'.length).trim();
      final String unquoted = raw.replaceAll('"', '').replaceAll("'", '');
      if (unquoted.isNotEmpty) title = unquoted;
    }
    return const _FrontMatter(consumedLines: 0, title: null);
  }
}

/// L'ouverture d'un bloc de code.
final class _FenceStart {
  const _FenceStart({required this.marker, required this.language});

  /// Le marqueur du debut de bloc (``` ou ~~~).
  final String marker;

  /// Le langage annonce, vide quand le bloc n'en annonce aucun.
  final String language;

  /// L'ouverture de bloc de code de [line], `null` quand la ligne n'en est
  /// pas une.
  static _FenceStart? of(String line) {
    final RegExp pattern = RegExp(r'^\s{0,3}(`{3,}|~{3,})\s*(\S*)\s*$');
    final RegExpMatch? match = pattern.firstMatch(line);
    if (match == null) return null;
    return _FenceStart(marker: match.group(1)!, language: match.group(2) ?? '');
  }
}

/// La fermeture d'un bloc de code.
bool _closesFence(String line, String fence) {
  final RegExp pattern = RegExp(
    '^\\s{0,3}${RegExp.escape(fence[0])}{${fence.length},}\\s*\$',
  );
  return pattern.hasMatch(line);
}

/// Un titre Markdown.
final class _Heading {
  const _Heading({required this.text, required this.level});

  /// Le texte du titre.
  final String text;

  /// Le niveau du titre.
  final int level;

  /// Le titre de [line], `null` quand la ligne n'en est pas un.
  static _Heading? of(String line) {
    final RegExp pattern = RegExp(r'^\s{0,3}(#{1,6})\s*(.*?)\s*#*\s*$');
    final RegExpMatch? match = pattern.firstMatch(line);
    if (match == null) return null;
    final int level = match.group(1)!.length;
    return _Heading(text: match.group(2) ?? '', level: level);
  }
}

/// Un element de liste Markdown.
final class _ListItem {
  const _ListItem({
    required this.text,
    required this.level,
    required this.isOrdered,
  });

  /// Le texte de l'element.
  final String text;

  /// La profondeur de l'element.
  final int level;

  /// Whether the item belongs to an ordered list.
  final bool isOrdered;

  /// L'element de liste de [line], `null` quand la ligne n'en est pas un.
  static _ListItem? of(String line) {
    final RegExp pattern = RegExp(r'^(\s*)([-*+]|\d+[.)])\s+(.*)$');
    final RegExpMatch? match = pattern.firstMatch(line);
    if (match == null) return null;
    final String indent = match.group(1)!;
    final String marker = match.group(2)!;
    final int depth = indent.length ~/ 2;
    return _ListItem(
      text: match.group(3)!.trim(),
      level: depth + 1,
      isOrdered: RegExp(r'^\d').hasMatch(marker),
    );
  }
}

/// Une ligne de citation.
final class _Quote {
  const _Quote({required this.text});

  /// Le texte de la citation.
  final String text;

  /// La ligne de citation de [line], `null` quand la ligne n'en est pas une.
  static _Quote? of(String line) {
    final RegExp pattern = RegExp(r'^\s{0,3}>\s?(.*)$');
    final RegExpMatch? match = pattern.firstMatch(line);
    if (match == null) return null;
    return _Quote(text: match.group(1)!.trim());
  }
}

/// Whether [line] is a thematic break.
///
/// Le separateur horizontal (`***`, `---`, `___`) coupe la scene : c'est
/// l'equivalent Markdown d'un saut de page.
bool _isThematicBreak(String line) {
  final RegExp pattern = RegExp(r'^\s{0,3}((\*\s*){3,}|(-\s*){3,}|(_ ?){3,})$');
  return pattern.hasMatch(line);
}
