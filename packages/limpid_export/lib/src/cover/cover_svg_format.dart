/// Formatting of the values written in an SVG document.
///
/// The formatting is locale independent: the same book always produces the
/// same bytes.
class CoverSvgFormat {
  const CoverSvgFormat._();

  /// Formats a length or an opacity.
  ///
  /// Whole numbers are written without a decimal part; the others keep two
  /// decimals.
  static String number(double value) {
    if (value == value.roundToDouble()) {
      return value.round().toString();
    }
    return value.toStringAsFixed(2);
  }
}
