import 'dart:convert';

import 'package:shelf/shelf.dart';

import '../errors/app_exception.dart';

/// A validated JSON request body.
///
/// Every accessor returns a typed value or throws a [ValidationException]
/// naming the faulty field, so an untyped map never travels past the parsing
/// layer.
final class JsonBody {
  /// Creates a body from an already decoded map.
  const JsonBody(this._fields);

  /// Decodes [raw] and checks that it holds a JSON object.
  factory JsonBody.decode(String raw) {
    if (raw.trim().isEmpty) {
      throw const ValidationException(
        field: 'body',
        message: 'Le corps de la requête est vide.',
      );
    }
    final Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } on FormatException catch (error) {
      throw ValidationException(
        field: 'body',
        message: 'Le corps de la requête n\'est pas un JSON valide.',
        details: <String, Object?>{'reason': error.message},
      );
    }
    if (decoded is! Map<String, dynamic>) {
      throw const ValidationException(
        field: 'body',
        message: 'Le corps de la requête doit être un objet JSON.',
      );
    }
    return JsonBody(decoded);
  }

  /// Reads and decodes the body of [request].
  static Future<JsonBody> fromRequest(
    Request request, {
    required int maxBytes,
  }) async {
    final int? length = request.contentLength;
    if (length != null && length > maxBytes) {
      throw PayloadTooLargeException(
        limitBytes: maxBytes,
        message: 'Le corps de la requête dépasse la taille maximale autorisée.',
      );
    }
    return JsonBody.decode(await request.readAsString());
  }

  final Map<String, dynamic> _fields;

  /// The decoded fields.
  Map<String, dynamic> get fields => Map<String, dynamic>.unmodifiable(_fields);

  /// The canonical JSON representation of the body.
  ///
  /// The fields are encoded in the order they were decoded: two bodies
  /// carrying the same fields produce the same representation, whatever the
  /// spacing of the request. The representation is the fingerprint of the
  /// body for the idempotency keys.
  String get canonicalJson => jsonEncode(_fields);

  /// Whether the body carries [field].
  bool has(String field) => _fields.containsKey(field);

  /// Reads a mandatory string.
  String requireString(String field, {int minLength = 1, int? maxLength}) {
    final Object? value = _fields[field];
    if (value == null) {
      throw ValidationException(
        field: field,
        message: 'Le champ « $field » est obligatoire.',
      );
    }
    if (value is! String) {
      throw ValidationException(
        field: field,
        message: 'Le champ « $field » doit être une chaîne de caractères.',
      );
    }
    if (value.trim().length < minLength) {
      throw ValidationException(
        field: field,
        message:
            'Le champ « $field » doit contenir au moins $minLength '
            'caractère(s).',
      );
    }
    if (maxLength != null && value.length > maxLength) {
      throw ValidationException(
        field: field,
        message:
            'Le champ « $field » ne doit pas dépasser $maxLength '
            'caractères.',
      );
    }
    return value;
  }

  /// Reads an optional string, ignoring an explicit `null`.
  String? optionalString(String field, {int maxLength = 4096}) {
    final Object? value = _fields[field];
    if (value == null) return null;
    if (value is! String) {
      throw ValidationException(
        field: field,
        message: 'Le champ « $field » doit être une chaîne de caractères.',
      );
    }
    if (value.length > maxLength) {
      throw ValidationException(
        field: field,
        message:
            'Le champ « $field » ne doit pas dépasser $maxLength '
            'caractères.',
      );
    }
    return value;
  }

  /// Reads a mandatory integer.
  int requireInt(String field, {int? min, int? max}) {
    final Object? value = _fields[field];
    if (value == null) {
      throw ValidationException(
        field: field,
        message: 'Le champ « $field » est obligatoire.',
      );
    }
    if (value is! int) {
      throw ValidationException(
        field: field,
        message: 'Le champ « $field » doit être un entier.',
      );
    }
    if (min != null && value < min) {
      throw ValidationException(
        field: field,
        message: 'Le champ « $field » doit être supérieur ou égal à $min.',
      );
    }
    if (max != null && value > max) {
      throw ValidationException(
        field: field,
        message: 'Le champ « $field » doit être inférieur ou égal à $max.',
      );
    }
    return value;
  }

  /// Reads an optional integer, ignoring an explicit `null`.
  int? optionalInt(String field, {int? min, int? max}) {
    final Object? value = _fields[field];
    if (value == null) return null;
    if (value is! int) {
      throw ValidationException(
        field: field,
        message: 'Le champ « $field » doit être un entier.',
      );
    }
    if (min != null && value < min) {
      throw ValidationException(
        field: field,
        message: 'Le champ « $field » doit être supérieur ou égal à $min.',
      );
    }
    if (max != null && value > max) {
      throw ValidationException(
        field: field,
        message: 'Le champ « $field » doit être inférieur ou égal à $max.',
      );
    }
    return value;
  }

  /// Reads a mandatory boolean.
  bool requireBool(String field) {
    final Object? value = _fields[field];
    if (value == null) {
      throw ValidationException(
        field: field,
        message: 'Le champ « $field » est obligatoire.',
      );
    }
    if (value is! bool) {
      throw ValidationException(
        field: field,
        message: 'Le champ « $field » doit être un booléen.',
      );
    }
    return value;
  }

  /// Reads an optional boolean.
  bool? optionalBool(String field) {
    final Object? value = _fields[field];
    if (value == null) return null;
    if (value is! bool) {
      throw ValidationException(
        field: field,
        message: 'Le champ « $field » doit être un booléen.',
      );
    }
    return value;
  }

  /// Reads a mandatory nested object.
  Map<String, dynamic> requireObject(String field) {
    final Object? value = _fields[field];
    if (value == null) {
      throw ValidationException(
        field: field,
        message: 'Le champ « $field » est obligatoire.',
      );
    }
    if (value is! Map<String, dynamic>) {
      throw ValidationException(
        field: field,
        message: 'Le champ « $field » doit être un objet JSON.',
      );
    }
    return value;
  }

  /// Reads a mandatory list.
  List<dynamic> requireList(String field, {int? minLength, int? maxLength}) {
    final Object? value = _fields[field];
    if (value == null) {
      throw ValidationException(
        field: field,
        message: 'Le champ « $field » est obligatoire.',
      );
    }
    if (value is! List<dynamic>) {
      throw ValidationException(
        field: field,
        message: 'Le champ « $field » doit être une liste.',
      );
    }
    if (minLength != null && value.length < minLength) {
      throw ValidationException(
        field: field,
        message:
            'Le champ « $field » doit contenir au moins $minLength '
            'élément(s).',
      );
    }
    if (maxLength != null && value.length > maxLength) {
      throw ValidationException(
        field: field,
        message:
            'Le champ « $field » ne doit pas contenir plus de '
            '$maxLength élément(s).',
      );
    }
    return value;
  }

  /// Reads a mandatory value of a closed set.
  T requireEnum<T extends Enum>(String field, List<T> allowed) {
    final String raw = requireString(field);
    for (final T candidate in allowed) {
      if (candidate.name == raw) return candidate;
    }
    throw ValidationException(
      field: field,
      message:
          'Le champ « $field » doit valoir '
          '${allowed.map((T value) => value.name).join(', ')}.',
    );
  }
}
