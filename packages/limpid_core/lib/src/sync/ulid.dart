import 'dart:math' as math;

import 'package:limpid_core/src/errors.dart';

/// Crockford base32 alphabet used by the ULID specification.
///
/// The letters `I`, `L`, `O` and `U` are excluded to avoid transcription
/// mistakes.
const String _alphabet = '0123456789ABCDEFGHJKMNPQRSTVWXYZ';

/// Length of the textual representation of a ULID.
const int _ulidLength = 26;

/// Number of random bits carried by a ULID.
const int _randomBits = 80;

/// A ULID: a globally unique, lexicographically sortable identifier.
///
/// The textual form packs a 48 bit millisecond timestamp and 80 random bits
/// into 26 Crockford base32 characters, so identifiers created later always
/// sort after identifiers created earlier.
final class Ulid implements Comparable<Ulid> {
  const Ulid._(this.value, this.timestampMilliseconds, this.randomPart);

  /// Builds a ULID from its parts.
  ///
  /// Throws an [InvalidSyncOperationException] when the timestamp is negative
  /// or when [randomPart] does not fit in 80 bits.
  factory Ulid.fromParts({
    required DateTime timestamp,
    required BigInt randomPart,
  }) {
    final milliseconds = timestamp.toUtc().millisecondsSinceEpoch;
    if (milliseconds < 0) {
      throw const InvalidSyncOperationException(
        'A ULID timestamp cannot be negative.',
      );
    }
    if (randomPart.isNegative || randomPart >= BigInt.one << _randomBits) {
      throw const InvalidSyncOperationException(
        'A ULID random part must fit in 80 bits.',
      );
    }
    final buffer = StringBuffer()
      ..write(_encodeTimestamp(milliseconds))
      ..write(_encodeRandom(randomPart));
    return Ulid._(buffer.toString(), milliseconds, randomPart);
  }

  /// Parses the textual representation of a ULID.
  ///
  /// Throws an [InvalidSyncOperationException] when the input is malformed.
  factory Ulid.parse(String value) {
    if (value.length != _ulidLength) {
      throw InvalidSyncOperationException(
        'A ULID must be $_ulidLength characters long, got "${value.length}".',
      );
    }
    var timestamp = 0;
    for (var i = 0; i < 10; i++) {
      final digit = _decodeChar(value.codeUnitAt(i));
      timestamp = (timestamp << 5) | digit;
    }
    var random = BigInt.zero;
    for (var i = 10; i < _ulidLength; i++) {
      final digit = _decodeChar(value.codeUnitAt(i));
      random = (random << 5) | BigInt.from(digit);
    }
    return Ulid._(value, timestamp, random);
  }

  /// The textual representation of the identifier.
  final String value;

  /// Milliseconds since the Unix epoch encoded in the identifier.
  final int timestampMilliseconds;

  /// The random part of the identifier.
  final BigInt randomPart;

  /// The creation time encoded in the identifier.
  DateTime get timestamp =>
      DateTime.fromMillisecondsSinceEpoch(timestampMilliseconds, isUtc: true);

  @override
  int compareTo(Ulid other) => value.compareTo(other.value);

  /// Whether this identifier was created strictly before [other].
  bool isBefore(Ulid other) => compareTo(other) < 0;

  @override
  bool operator ==(Object other) =>
      identical(this, other) || (other is Ulid && other.value == value);

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => value;

  static String _encodeTimestamp(int milliseconds) {
    final buffer = StringBuffer();
    var remaining = milliseconds;
    for (var i = 0; i < 10; i++) {
      buffer.write(_alphabet[remaining & 31]);
      remaining >>= 5;
    }
    return buffer.toString().split('').reversed.join();
  }

  static String _encodeRandom(BigInt random) {
    final buffer = StringBuffer();
    var remaining = random;
    for (var i = 0; i < 16; i++) {
      buffer.write(_alphabet[(remaining & BigInt.from(31)).toInt()]);
      remaining = remaining >> 5;
    }
    return buffer.toString().split('').reversed.join();
  }

  static int _decodeChar(int code) {
    const String uppercase = '0123456789ABCDEFGHJKMNPQRSTVWXYZ';
    const String lowercase = 'abcdefghjkmnpqrstvwxyz';
    final char = String.fromCharCode(code);
    final index = uppercase.indexOf(char);
    if (index >= 0) return index;
    final lowerIndex = lowercase.indexOf(char);
    if (lowerIndex >= 0) return lowerIndex;
    throw InvalidSyncOperationException('Invalid ULID character "$char".');
  }
}

/// Generates ULID identifiers.
///
/// The generator keeps the identifiers strictly increasing: two identifiers
/// created during the same millisecond keep the previous random part and
/// increment it, so the textual order always matches the creation order.
final class UlidGenerator {
  /// Creates a generator.
  ///
  /// [random] defaults to a cryptographically secure source and [clock]
  /// defaults to the wall clock.
  UlidGenerator({math.Random? random, DateTime Function()? clock})
    : _random = random ?? math.Random.secure(),
      _clock = clock ?? DateTime.now;

  final math.Random _random;
  final DateTime Function() _clock;

  int _lastMilliseconds = -1;
  BigInt _lastRandom = BigInt.zero;

  /// Generates the next identifier.
  Ulid generate() {
    final now = _clock().toUtc().millisecondsSinceEpoch;
    // A clock that goes backwards (or two calls inside the same millisecond)
    // must not produce an identifier that sorts before the previous one.
    final isMonotonic = now <= _lastMilliseconds;
    final milliseconds = isMonotonic ? _lastMilliseconds : now;
    final randomPart = isMonotonic
        ? (_lastRandom + BigInt.one) & _randomMask
        : _drawRandom();
    _lastMilliseconds = milliseconds;
    _lastRandom = randomPart;
    return Ulid.fromParts(
      timestamp: DateTime.fromMillisecondsSinceEpoch(milliseconds, isUtc: true),
      randomPart: randomPart,
    );
  }

  /// Le nombre de valeurs d'un tirage de 32 bits.
  ///
  /// La borne est ecrite **en hexadecimal**, et non `1 << 32` : sur le
  /// web, le compilateur Dart2JS replie la constante `1 << 32` a zero, et
  /// le tirage devient `nextInt(0)`, qui leve une `RangeError`. Le tirage
  /// echoue alors **au moment de creer un identifiant** — c'est-a-dire au
  /// moment de creer un projet, une scene, un chapitre — et l'erreur
  /// traversant les `on Exception`, l'interface ne montre rien.
  ///
  /// La valeur 0x1_0000_0000 est la meme que 2^32 : le tirage produit un
  /// entier dans [0, 2^32), soit 32 bits.
  static const int _full32 = 0x100000000;

  BigInt _drawRandom() {
    final high = _random.nextInt(_full32);
    final mid = _random.nextInt(_full32);
    final low = _random.nextInt(1 << 16);
    return (BigInt.from(high) << 48) |
        (BigInt.from(mid) << 16) |
        BigInt.from(low);
  }

  static final BigInt _randomMask = (BigInt.one << _randomBits) - BigInt.one;
}
