/// Formats a number with a space between the thousands.
///
/// The French typography separates the thousands with a space: the format is
/// shared by the dashboard and the library, so that the same figure is
/// written the same way everywhere.
String formatCount(int value) {
  final String digits = value.abs().toString();
  final StringBuffer buffer = StringBuffer(value < 0 ? '-' : '');
  for (int index = 0; index < digits.length; index++) {
    if (index > 0 && (digits.length - index) % 3 == 0) {
      buffer.write(' ');
    }
    buffer.write(digits[index]);
  }
  return buffer.toString();
}
