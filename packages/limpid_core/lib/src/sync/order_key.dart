import 'package:limpid_core/src/errors.dart';

/// A fractional index used to order siblings inside the manuscript tree.
///
/// The key is a string of decimal digits interpreted as the fraction
/// `0.<digits>`. Keys are compared **lexicographically as strings**, never as
/// floating point numbers, so ordering is exact and stable across platforms.
///
/// ## Canonical form
///
/// A canonical key never ends with a `0` (except the single key `0`, used as
/// the lower sentinel). Removing the trailing zeros of a fraction keeps its
/// value and guarantees that two distinct keys never denote the same
/// position. Leading zeros are significant: `05` denotes `0.05` while `5`
/// denotes `0.5`.
///
/// ## Generation
///
/// [OrderKey.between] computes a key strictly between two neighbours without
/// ever rewriting an existing key, which is what makes concurrent insertions
/// converge: two authors inserting at the same spot obtain two different
/// keys and the lexicographic comparison orders them deterministically.
///
/// The arithmetic is carried out on decimal digit strings, so the keys stay
/// exact whatever their length.
final class OrderKey implements Comparable<OrderKey> {
  const OrderKey._(this.value);

  /// Creates a key from its canonical textual representation.
  ///
  /// Throws an [InvalidSyncOperationException] when [value] is not a
  /// canonical key.
  factory OrderKey(String value) {
    if (value.isEmpty) {
      throw const InvalidSyncOperationException(
        'An order key cannot be empty.',
      );
    }
    for (var i = 0; i < value.length; i++) {
      final code = value.codeUnitAt(i);
      if (code < _zeroCode || code > _nineCode) {
        throw InvalidSyncOperationException(
          'An order key can only contain digits, got "$value".',
        );
      }
    }
    if (value.length > 1 && value.endsWith('0')) {
      throw InvalidSyncOperationException(
        'An order key must be canonical (no trailing zero), got "$value".',
      );
    }
    return OrderKey._(value);
  }

  /// The canonical textual representation with the key.
  final String value;

  /// The sentinel key used as the lower bound of the key space.
  static const OrderKey zero = OrderKey._('0');

  /// The key given to the very first element of a list.
  static const OrderKey initial = OrderKey._('5');

  static const int _zeroCode = 0x30;
  static const int _nineCode = 0x39;

  /// Returns a key strictly between [lower] and [upper].
  ///
  /// Either bound may be `null`, meaning "before the first key" or "after the
  /// last key". The returned key is always canonical and never equals an
  /// existing key.
  ///
  /// Throws an [InvalidSyncOperationException] when [lower] is not strictly
  /// before [upper].
  static OrderKey between(OrderKey? lower, OrderKey? upper) {
    if (lower != null && upper != null) {
      if (lower.compareTo(upper) >= 0) {
        throw InvalidSyncOperationException(
          'Order keys are not strictly ordered: "$lower" then "$upper".',
        );
      }
      return OrderKey._(_midpoint(lower.value, upper.value));
    }
    if (lower == null && upper == null) {
      return initial;
    }
    if (lower == null) {
      return OrderKey._(_midpoint(zero.value, upper!.value));
    }
    return OrderKey._(_midpointAbove(lower.value));
  }

  /// Computes the fraction strictly between two canonical digit strings.
  static String _midpoint(String lower, String upper) {
    final scale = lower.length > upper.length ? lower.length : upper.length;
    final sum = _addDigits(_padRight(lower, scale), _padRight(upper, scale));
    return _canonicalize(_halve(sum, scale));
  }

  /// Computes the fraction strictly between [lower] and the fraction one.
  static String _midpointAbove(String lower) {
    final scale = lower.length;
    // The fraction one is the digit string "1" followed by `scale` zeros.
    final one = '1${'0' * scale}';
    final sum = _addDigits(lower, one);
    return _canonicalize(_halve(sum, scale));
  }

  /// Adds two decimal digit strings, right aligned.
  static String _addDigits(String left, String right) {
    final length = left.length > right.length ? left.length : right.length;
    final result = List<String>.filled(length + 1, '0');
    var leftIndex = left.length - 1;
    var rightIndex = right.length - 1;
    var carry = 0;
    for (var i = length - 1; i >= 0; i--) {
      var sum = carry;
      if (leftIndex >= 0) sum += left.codeUnitAt(leftIndex) - _zeroCode;
      if (rightIndex >= 0) sum += right.codeUnitAt(rightIndex) - _zeroCode;
      result[i + 1] = String.fromCharCode(_zeroCode + sum % 10);
      carry = sum ~/ 10;
      leftIndex--;
      rightIndex--;
    }
    result[0] = String.fromCharCode(_zeroCode + carry);
    return result.join();
  }

  /// Halves the integer written by [digits] and expresses the result on
  /// [scale] decimals.
  ///
  /// When the half is not exact, one extra decimal digit is produced so that
  /// the result stays exact.
  static String _halve(String digits, int scale) {
    final quotient = StringBuffer();
    var remainder = 0;
    for (var i = 0; i < digits.length; i++) {
      final value = remainder * 10 + (digits.codeUnitAt(i) - _zeroCode);
      quotient.writeCharCode(_zeroCode + value ~/ 2);
      remainder = value % 2;
    }
    final text = _stripLeadingZeros(quotient.toString());
    final padded = text.padLeft(scale, '0');
    return remainder == 0 ? padded : '${padded}5';
  }

  /// Removes the leading zeros of a digit string, keeping at least one digit.
  static String _stripLeadingZeros(String digits) {
    var start = 0;
    while (start < digits.length - 1 && digits.codeUnitAt(start) == _zeroCode) {
      start++;
    }
    return digits.substring(start);
  }

  /// Appends zeros to [value] until it reaches [length] digits.
  static String _padRight(String value, int length) {
    if (value.length >= length) return value;
    return value.padRight(length, '0');
  }

  /// Removes the trailing zeros of a digit string, keeping at least one digit.
  static String _canonicalize(String digits) {
    var end = digits.length;
    while (end > 1 && digits.codeUnitAt(end - 1) == _zeroCode) {
      end--;
    }
    return digits.substring(0, end);
  }

  @override
  int compareTo(OrderKey other) => value.compareTo(other.value);

  /// Whether this key is strictly before [other].
  bool isBefore(OrderKey other) => compareTo(other) < 0;

  /// Whether this key is strictly after [other].
  bool isAfter(OrderKey other) => compareTo(other) > 0;

  @override
  bool operator ==(Object other) =>
      identical(this, other) || (other is OrderKey && other.value == value);

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => value;
}
