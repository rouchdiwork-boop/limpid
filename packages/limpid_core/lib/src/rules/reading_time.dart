import 'package:limpid_core/src/rules/word_count.dart';

/// Estimates the reading time of a manuscript.
///
/// The estimation uses a constant words-per-minute rate, the convention used
/// by the publishing platforms.
final class ReadingTimeEstimator {
  const ReadingTimeEstimator({this.wordsPerMinute = defaultWordsPerMinute});

  /// The default reading speed, in words per minute.
  static const int defaultWordsPerMinute = 200;

  /// The reading speed used by the estimator.
  final int wordsPerMinute;

  /// The estimated reading time of [wordCount] words.
  Duration estimate(int wordCount) {
    if (wordCount <= 0) return Duration.zero;
    final minutes = wordCount / wordsPerMinute;
    return Duration(seconds: (minutes * 60).round());
  }

  /// The estimated reading time of [text].
  Duration estimateText(String text) => estimate(WordCount.ofText(text));

  /// The number of pages of a manuscript, using [wordsPerPage].
  int estimatePages(int wordCount, {int wordsPerPage = defaultWordsPerPage}) {
    if (wordCount <= 0) return 0;
    return (wordCount / wordsPerPage).ceil();
  }

  /// The default number of words of a printed page.
  static const int defaultWordsPerPage = 300;
}
