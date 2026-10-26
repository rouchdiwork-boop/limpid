import '../model/export_book.dart';
import 'cover_color.dart';
import 'cover_tokens.dart';

/// The colours of a generated cover.
///
/// The palette of a book is derived from its identifier, exactly like the
/// covers of the application: the same book always keeps the same colour,
/// in the application and in its exports.
class CoverPalette {
  /// Creates a palette.
  const CoverPalette({
    required this.index,
    required this.seed,
    required this.base,
    required this.shade,
    required this.ink,
  });

  /// Derives the palette of a book from its identifier.
  factory CoverPalette.forBook(ExportBook book) {
    final seed = coverSeedOf(book);
    final index = seed % CoverTokens.palette.length;
    final base = CoverTokens.palette[index];
    return CoverPalette(
      index: index,
      seed: seed,
      base: base,
      shade: CoverColor.mix(base, CoverTokens.shade, CoverPalette.shadeRatio),
      ink: CoverTokens.ink,
    );
  }

  /// The share of the shade in the gradient of the cover.
  ///
  /// The application shades its covers towards the foreground with the same
  /// ratio.
  static const double shadeRatio = 0.55;

  /// The index of the palette, between zero and the number of palettes.
  final int index;

  /// The seed the palette was derived from.
  final int seed;

  /// The dominant colour of the cover.
  final String base;

  /// The colour the gradient ends on.
  final String shade;

  /// The colour of the text printed on the cover.
  final String ink;

  @override
  String toString() => 'CoverPalette($index, $base)';
}

/// The palette seed of a book, derived from its identifier.
///
/// The identifier of the book is used first, then its ISBN, then its title.
/// The computation is the one of the application (`coverSeedOf`), so both
/// draw the same book with the same colour.
int coverSeedOf(ExportBook book) {
  final identifier =
      book.metadata.identifier ?? book.metadata.isbn ?? book.title;
  var hash = 0;
  for (final code in identifier.codeUnits) {
    hash = (hash * 31 + code) & 0x7fffffff;
  }
  return hash;
}
