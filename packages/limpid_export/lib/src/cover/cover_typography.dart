import '../fonts/embedded_font.dart';

/// The typography of the generated covers.
///
/// The cover borrows the spirit of the mockup: a display serif for the
/// title, a manuscript serif for the author. Both families are the ones the
/// application embeds (`lib/src/fonts/embedded_font.dart`, cf. D-13), so the
/// exported cover speaks the same language as the book it belongs to.
///
/// The sizes are expressed against the width of the face: the cover is
/// printed at 300 dpi and its text must scale with it.
class CoverTypography {
  const CoverTypography._();

  /// The display serif used for the title.
  static const String titleFamily = 'Fraunces';

  /// The manuscript serif used for the author.
  static const String authorFamily = 'Literata';

  /// The size of the title, against the width of the face.
  static const double titleSizeRatio = 0.115;

  /// The smallest size the title can take, against the width of the face.
  static const double minTitleSizeRatio = 0.07;

  /// The size of the author, against the width of the face.
  static const double authorSizeRatio = 0.058;

  /// The size of the label printed above the title, against the width of the
  /// face.
  static const double labelSizeRatio = 0.03;

  /// The size of the summary of the back cover, against the width of the
  /// face.
  static const double summarySizeRatio = 0.032;

  /// The size of the title on the spine, against the width of the face.
  static const double spineTitleSizeRatio = 0.042;

  /// The size of the author on the spine, against the width of the face.
  static const double spineAuthorSizeRatio = 0.026;

  /// The line height of the title.
  static const double titleLineHeight = 1.06;

  /// The line height of the summary of the back cover.
  static const double summaryLineHeight = 1.45;

  /// The tracking of the author, against its size.
  static const double authorLetterSpacingRatio = 0.09;

  /// The tracking of the label, against its size.
  static const double labelLetterSpacingRatio = 0.14;

  /// The number of lines the title can take.
  static const int maxTitleLines = 4;

  /// The font stack of the title: the embedded family first, then the
  /// generic serif every renderer knows.
  static String get titleStack => stackOf(titleFamily);

  /// The font stack of the author.
  static String get authorStack => stackOf(authorFamily);

  /// Builds the font stack of an embedded family.
  static String stackOf(String family) =>
      '$family, Georgia, "Times New Roman", serif';

  /// Whether the family is one of the families the application embeds.
  static bool isEmbedded(String family) =>
      LimpidFonts.families.contains(family);

  /// The size of the title on a face of the given width.
  static double titleSize(double faceWidth) => faceWidth * titleSizeRatio;

  /// The smallest size the title can take on a face of the given width.
  static double minTitleSize(double faceWidth) => faceWidth * minTitleSizeRatio;

  /// The size of the author on a face of the given width.
  static double authorSize(double faceWidth) => faceWidth * authorSizeRatio;

  /// The size of the label printed above the title.
  static double labelSize(double faceWidth) => faceWidth * labelSizeRatio;

  /// The size of the summary of the back cover.
  static double summarySize(double faceWidth) => faceWidth * summarySizeRatio;

  /// The size of the title on the spine.
  static double spineTitleSize(double faceWidth) =>
      faceWidth * spineTitleSizeRatio;

  /// The size of the author on the spine.
  static double spineAuthorSize(double faceWidth) =>
      faceWidth * spineAuthorSizeRatio;
}
