import 'dart:convert';
import 'dart:math' as math;

import 'package:crypto/crypto.dart';
import 'package:limpid_ai/src/rag/rag_index.dart';

/// Embedder de référence, déterministe et entièrement hors-ligne.
///
/// Chaque mot du texte est projeté dans un vecteur grâce à une empreinte
/// SHA-256 : le nombre d'occurrences est porté par le poids, la position dans
/// le vecteur par l'empreinte. Deux textes proches lexicalement obtiennent
/// donc des vecteurs proches.
///
/// Cet embedder ne remplace pas un modèle d'embeddings : il sert au mode local
/// et aux tests. L'API Limpid fournit l'embedder de production.
class HashingEmbeddingProvider implements AiEmbeddingProvider {
  /// Crée un embedder.
  const HashingEmbeddingProvider({this.dimensions = 256});

  /// Taille des vecteurs produits.
  @override
  final int dimensions;

  /// Calcule l'embedding d'un texte.
  @override
  Future<List<double>> embed(String text) async => embedSync(text);

  /// Calcule l'embedding d'un texte de façon synchrone.
  List<double> embedSync(String text) {
    final List<double> vector = List<double>.filled(dimensions, 0);
    if (dimensions <= 0) {
      return vector;
    }
    for (final String token in _tokenize(text)) {
      final List<int> digest = sha256.convert(utf8.encode(token)).bytes;
      final int bucket = _readInt(digest, 0) % dimensions;
      final double sign = _readInt(digest, 4) % 2 == 0 ? 1 : -1;
      vector[bucket] += sign;
    }
    return _normalize(vector);
  }

  List<String> _tokenize(String text) {
    return text
        .toLowerCase()
        .split(RegExp('[^a-z0-9]+'))
        .where((String token) => token.isNotEmpty)
        .toList(growable: false);
  }

  int _readInt(List<int> bytes, int offset) {
    int value = 0;
    for (int index = 0; index < 4; index++) {
      value = (value << 8) | bytes[offset + index];
    }
    return value & 0x7fffffff;
  }

  List<double> _normalize(List<double> vector) {
    double sum = 0;
    for (final double value in vector) {
      sum += value * value;
    }
    if (sum <= 0) {
      return vector;
    }
    final double norm = math.sqrt(sum);
    return vector.map((double value) => value / norm).toList(growable: false);
  }
}
