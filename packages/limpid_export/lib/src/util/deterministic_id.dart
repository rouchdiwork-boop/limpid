import 'dart:convert';
import 'dart:typed_data';

/// Identifiants deterministes derives d'une chaine.
///
/// Le moteur d'export ne depend d'aucun service externe et ne dispose pas
/// d'UUID aleatoire : les identifiants d'ouvrage sont donc derives du
/// contenu, afin que deux exports du meme livre produisent le meme fichier.
class DeterministicIds {
  const DeterministicIds._();

  static const int _prime1 = 2147483647;
  static const int _prime2 = 2147483629;
  static const int _prime3 = 2147483587;
  static const int _prime4 = 2147483579;

  /// Derive un identifiant UUID (forme version 5) d'une chaine libre.
  static String uuidFrom(String seed) {
    final builder = BytesBuilder()
      ..add(_bytes(_hash(seed, 17, _prime1), 4))
      ..add(_bytes(_hash(seed, 31, _prime2), 4))
      ..add(_bytes(_hash(seed, 47, _prime3), 4))
      ..add(_bytes(_hash(seed, 97, _prime4), 4));
    final bytes = builder.toBytes();

    // Version 5 et variante RFC 4122.
    bytes[6] = (bytes[6] & 0x0F) | 0x50;
    bytes[8] = (bytes[8] & 0x3F) | 0x80;

    final hex = bytes
        .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
        .join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
        '${hex.substring(12, 16)}-${hex.substring(16, 20)}-'
        '${hex.substring(20, 32)}';
  }

  static int _hash(String seed, int salt, int prime) {
    var hash = salt;
    for (final byte in utf8.encode(seed)) {
      hash = (hash * 31 + byte) % prime;
    }
    return hash;
  }

  static List<int> _bytes(int value, int count) {
    final result = List<int>.filled(count, 0);
    var remaining = value;
    for (var index = count - 1; index >= 0; index--) {
      result[index] = remaining & 0xFF;
      remaining >>= 8;
    }
    return result;
  }
}
