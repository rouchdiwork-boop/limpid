/// Colour helpers for the generated covers.
///
/// Colours travel as `#RRGGBB` strings: it is the format of the design
/// system tokens and the format SVG expects.
class CoverColor {
  const CoverColor._();

  /// Parses a `#RRGGBB` colour into its red, green and blue components.
  ///
  /// Throws a [FormatException] when the colour cannot be read.
  static (int red, int green, int blue) parse(String hex) {
    final normalized = hex.startsWith('#') ? hex.substring(1) : hex;
    if (normalized.length != 6) {
      throw FormatException('Couleur invalide : $hex', hex);
    }
    final value = int.tryParse(normalized, radix: 16);
    if (value == null) {
      throw FormatException('Couleur invalide : $hex', hex);
    }
    return ((value >> 16) & 0xFF, (value >> 8) & 0xFF, value & 0xFF);
  }

  /// Formats red, green and blue components as `#RRGGBB`.
  static String toHex(int red, int green, int blue) {
    return '#${_component(red)}${_component(green)}${_component(blue)}';
  }

  /// Mixes two colours.
  ///
  /// [ratio] is the share of [to] in the result: `0` returns [from], `1`
  /// returns [to].
  static String mix(String from, String to, double ratio) {
    final share = ratio.clamp(0.0, 1.0).toDouble();
    final source = parse(from);
    final target = parse(to);
    return toHex(
      _blend(source.$1, target.$1, share),
      _blend(source.$2, target.$2, share),
      _blend(source.$3, target.$3, share),
    );
  }

  static int _blend(int from, int to, double share) =>
      (from + (to - from) * share).round();

  static String _component(int value) =>
      value.toRadixString(16).padLeft(2, '0').toUpperCase();
}
