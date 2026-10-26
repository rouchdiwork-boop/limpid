import 'dart:convert';

import 'package:limpid_ai/src/model/ai_error.dart';

/// Lecture défensive du JSON renvoyé par une fournisseur.
///
/// Aucune exception de parsing n'est laissée remonter telle quelle : elle est
/// convertie en [AiInvalidResponse], avec un message utilisateur en français.
class ProviderJson {
  const ProviderJson._();

  /// Décode un objet JSON.
  ///
  /// Lève [AiInvalidResponse] si le corps n'est pas un objet JSON valide.
  static Map<String, dynamic> asObject(
    String rawBody, {
    required String providerName,
  }) {
    final Object? decoded = _decode(rawBody);
    if (decoded is Map<String, dynamic>) {
      return decoded;
    }
    throw AiInvalidResponse(
      providerName: providerName,
      details: <String, String>{'reason': 'corps JSON non objet'},
    );
  }

  /// Décode un objet JSON sans lever d'exception.
  ///
  /// Renvoie `null` si le corps est illisible ou n'est pas un objet.
  static Map<String, dynamic>? tryAsObject(String rawBody) {
    final Object? decoded = _decode(rawBody);
    if (decoded is Map<String, dynamic>) {
      return decoded;
    }
    return null;
  }

  /// Lit une chaîne, avec une valeur de repli.
  static String asString(Object? value, {String fallback = ''}) {
    if (value is String) {
      return value;
    }
    if (value is num || value is bool) {
      return value.toString();
    }
    return fallback;
  }

  /// Lit un entier, avec une valeur de repli.
  static int asInt(Object? value, {int fallback = 0}) {
    if (value is int) {
      return value;
    }
    if (value is double) {
      return value.toInt();
    }
    if (value is String) {
      return int.tryParse(value) ?? fallback;
    }
    return fallback;
  }

  /// Lit un flottant, avec une valeur de repli.
  static double asDouble(Object? value, {double fallback = 0}) {
    if (value is double) {
      return value;
    }
    if (value is int) {
      return value.toDouble();
    }
    if (value is String) {
      return double.tryParse(value) ?? fallback;
    }
    return fallback;
  }

  /// Lit une liste, avec une valeur de repli.
  static List<Object?> asList(Object? value) {
    if (value is List<Object?>) {
      return value;
    }
    if (value is List<dynamic>) {
      return value.cast<Object?>();
    }
    return const <Object?>[];
  }

  /// Extrait le message d'erreur d'un corps JSON de fournisseur.
  ///
  /// Couvre le format Anthropic (`{"type":"error","error":{"message":...}}`)
  /// et le format OpenAI (`{"error":{"message":...}}`).
  static String? extractErrorMessage(String rawBody) {
    final Map<String, dynamic>? root = tryAsObject(rawBody);
    if (root == null) {
      return null;
    }
    final Object? error = root['error'];
    if (error is Map<String, dynamic>) {
      final String message = asString(error['message']);
      if (message.isNotEmpty) {
        return message;
      }
      final String type = asString(error['type']);
      if (type.isNotEmpty) {
        return type;
      }
    }
    final String topLevel = asString(root['message']);
    return topLevel.isEmpty ? null : topLevel;
  }

  static Object? _decode(String rawBody) {
    if (rawBody.trim().isEmpty) {
      return null;
    }
    try {
      return jsonDecode(rawBody);
    } on FormatException {
      return null;
    }
  }
}
