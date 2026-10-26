import '../model/import_block.dart';
import '../model/import_format.dart';
import '../model/import_request.dart';
import 'chapter_builder.dart';
import 'manuscript_reader.dart';
import 'parsed_document.dart';
import 'rtf_tokenizer.dart';
import 'text_decoding.dart';

/// La longueur maximale du texte d'un paragraphe accepte comme titre de
/// chapitre.
///
/// Un paragraphe plus long n'est pas un titre : c'est du texte. La regle
/// evite qu'un RTF sans titres perde son premier paragraphe.
const int maxRtfChapterTitleLength = 120;

/// Le lecteur de RTF.
///
/// Les titres sont donnes par le niveau de plan (`\outlinelevelN`) et par
/// les sections (`\sect`) ; les paragraphes sont delimites par `\par`. Un
/// saut de page (`\page`) coupe la scene.
final class RtfReader implements ManuscriptReader {
  /// Cree un lecteur RTF.
  const RtfReader();

  /// Les destinations RTF dont le contenu ne fait pas partie du texte.
  static const Set<String> skippedDestinations = <String>{
    'fonttbl',
    'colortbl',
    'stylesheet',
    'info',
    'pict',
    'listtable',
    'listoverridetable',
    'rsidtbl',
    'xmlnstbl',
    'themedata',
    'latentstyles',
    'colorschememapping',
    'datastore',
    'generator',
    'header',
    'footer',
    'headerl',
    'headerr',
    'footerl',
    'footerr',
  };

  @override
  ImportFormat get format => ImportFormat.rtf;

  @override
  ParsedDocument read(ImportRequest request) {
    final String source = decodeText(request.bytes);
    final List<RtfToken> tokens = tokenizeRtf(source);
    final ChapterBuilder builder = ChapterBuilder(
      defaultTitle: request.baseName,
    );

    var groupDepth = 0;
    int? skipUntilDepth;
    var unicodeSkip = false;
    var binSkip = 0;
    var outlineLevel = 0;
    var chapterTitlePending = true;
    int? highSurrogate;
    final StringBuffer paragraph = StringBuffer();

    void flushParagraph() {
      final String text = paragraph.toString().trim();
      final int level = outlineLevel;
      paragraph.clear();
      outlineLevel = 0;
      if (text.isEmpty) return;

      if (level >= 1) {
        builder.openChapter(text, level: level > 3 ? 3 : level);
        chapterTitlePending = false;
        return;
      }
      if (chapterTitlePending) {
        chapterTitlePending = false;
        if (text.length <= maxRtfChapterTitleLength) {
          builder.openChapter(text);
          return;
        }
      }
      builder.addBlock(
        ImportedBlock(type: ImportedBlockType.paragraph, text: text),
      );
    }

    void writeText(String text) {
      if (binSkip > 0) {
        final int dropped = binSkip > text.length ? text.length : binSkip;
        binSkip -= dropped;
        text = text.substring(dropped);
      }
      if (text.isEmpty) return;
      if (unicodeSkip) {
        unicodeSkip = false;
        text = text.substring(1);
        if (text.isEmpty) return;
      }
      paragraph.write(text);
    }

    void writeCodePoint(int value) {
      if (value >= 0xD800 && value <= 0xDBFF) {
        highSurrogate = value;
        return;
      }
      if (value >= 0xDC00 && value <= 0xDFFF) {
        final int? high = highSurrogate;
        highSurrogate = null;
        if (high == null) return;
        final int code = 0x10000 + ((high - 0xD800) << 10) + (value - 0xDC00);
        paragraph.writeCharCode(code);
        return;
      }
      highSurrogate = null;
      paragraph.writeCharCode(value);
    }

    for (final RtfToken token in tokens) {
      switch (token) {
        case RtfGroupStart():
          groupDepth++;
        case RtfGroupEnd():
          groupDepth--;
          if (skipUntilDepth != null && groupDepth <= skipUntilDepth) {
            skipUntilDepth = null;
          }
        case RtfHexEscape():
          if (skipUntilDepth != null) break;
          if (unicodeSkip) {
            unicodeSkip = false;
            break;
          }
          writeCodePoint(token.value);
        case RtfText():
          if (skipUntilDepth != null) break;
          writeText(token.text);
        case RtfControlWord():
          final RtfControlWord word = token;
          if (word.name == '*') {
            skipUntilDepth = groupDepth;
            break;
          }
          if (skippedDestinations.contains(word.name)) {
            skipUntilDepth = groupDepth;
            break;
          }
          if (skipUntilDepth != null) break;

          switch (word.name) {
            case 'par':
              flushParagraph();
            case 'pard':
              outlineLevel = 0;
            case 'sect':
              flushParagraph();
              builder.openChapter('');
              chapterTitlePending = true;
            case 'page':
              flushParagraph();
              builder.breakScene();
            case 'tab':
              paragraph.write('\t');
            case 'line':
              paragraph.write(' ');
            case 'u':
              final int value = word.parameter ?? 0;
              if (value > 0) writeCodePoint(value);
              unicodeSkip = true;
            case 'bin':
              binSkip = word.parameter ?? 0;
            case 'lquote':
              paragraph.write('‘');
            case 'rquote':
              paragraph.write('’');
            case 'ldblquote':
              paragraph.write('“');
            case 'rdblquote':
              paragraph.write('”');
            case 'emdash':
              paragraph.write('—');
            case 'endash':
              paragraph.write('–');
            case 'bullet':
              paragraph.write('•');
            case '~':
              paragraph.write(' ');
            case '_':
              paragraph.write('‑');
            default:
              if (word.name.startsWith('outlinelevel')) {
                outlineLevel = word.parameter ?? 0;
              }
          }
      }
    }
    flushParagraph();

    return builder.build(title: _titleOf(source));
  }

  /// Le titre porte par le groupe `{\info ...}` du document.
  static String? _titleOf(String source) {
    final int info = source.indexOf(r'{\info');
    if (info < 0) return null;
    final int end = source.indexOf('}', info);
    final String region = end < 0
        ? source.substring(info)
        : source.substring(info, end);
    final RegExpMatch? match = RegExp(
      r'\\title\s+([^\\{}\r\n]+)',
    ).firstMatch(region);
    if (match == null) return null;
    final String title = match.group(1)!.trim();
    return title.isEmpty ? null : title;
  }
}
