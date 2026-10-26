import 'package:limpid_core/src/domain/block.dart';
import 'package:limpid_core/src/domain/content.dart';
import 'package:limpid_core/src/domain/enums.dart';

/// Counts the words of a text.
///
/// Words are separated by any whitespace; punctuation does not create a word.
final class WordCount {
  const WordCount._();

  /// The number of words of [text].
  static int ofText(String text) {
    if (text.trim().isEmpty) return 0;
    return text.split(_whitespace).where((word) => word.isNotEmpty).length;
  }

  /// The number of words of [content].
  static int ofContent(BlockContent content) => ofText(content.plainText);

  /// The number of words of the prose blocks of [blocks].
  ///
  /// Headings, code blocks, images and scene breaks do not count towards the
  /// manuscript length.
  static int ofBlocks(Iterable<Block> blocks) {
    var total = 0;
    for (final block in blocks) {
      if (!isProseBlockType(block.type)) continue;
      total += ofContent(block.content);
    }
    return total;
  }

  /// The number of characters of [text], without the trailing whitespace.
  static int charactersOf(String text) => text.trimRight().length;

  /// The number of paragraphs of [text].
  ///
  /// A paragraph is a non-empty group of lines.
  static int paragraphsOf(String text) {
    var count = 0;
    for (final paragraph in text.split(_paragraphBreak)) {
      if (paragraph.trim().isNotEmpty) count++;
    }
    return count;
  }

  static final RegExp _whitespace = RegExp(r'\s+');
  static final RegExp _paragraphBreak = RegExp(r'\n\s*\n');
}
