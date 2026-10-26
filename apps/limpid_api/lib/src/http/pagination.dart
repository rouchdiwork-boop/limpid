import 'dart:convert';

import '../errors/app_exception.dart';

/// A validated pagination request.
///
/// The cursor is opaque: it encodes the sort key of the last item of the
/// previous page so the client never has to know the sort order.
final class PageRequest {
  /// Creates a page request.
  const PageRequest({
    required this.limit,
    required this.page,
    required this.cursor,
  });

  /// Builds a page request from the query string of a request.
  factory PageRequest.fromQuery(
    Map<String, String> query, {
    required int defaultLimit,
    required int maxLimit,
  }) {
    final int limit = _readLimit(
      query,
      defaultLimit: defaultLimit,
      maxLimit: maxLimit,
    );
    final int page = _readPage(query);
    final String? cursor = query['cursor'];
    return PageRequest(limit: limit, page: page, cursor: cursor);
  }

  /// The maximum number of items of a page.
  final int limit;

  /// The one-based number of the requested page.
  final int page;

  /// The opaque cursor pointing at the item the page starts after.
  final String? cursor;

  static int _readLimit(
    Map<String, String> query, {
    required int defaultLimit,
    required int maxLimit,
  }) {
    final String? raw = query['limit'];
    if (raw == null || raw.trim().isEmpty) return defaultLimit;
    final int? parsed = int.tryParse(raw.trim());
    if (parsed == null || parsed <= 0) {
      throw const ValidationException(
        field: 'limit',
        message:
            'Le paramètre « limit » doit être un entier strictement '
            'positif.',
      );
    }
    if (parsed > maxLimit) {
      throw ValidationException(
        field: 'limit',
        message: 'Le paramètre « limit » ne peut pas dépasser $maxLimit.',
      );
    }
    return parsed;
  }

  static int _readPage(Map<String, String> query) {
    final String? raw = query['page'];
    if (raw == null || raw.trim().isEmpty) return 1;
    final int? parsed = int.tryParse(raw.trim());
    if (parsed == null || parsed <= 0) {
      throw const ValidationException(
        field: 'page',
        message:
            'Le paramètre « page » doit être un entier strictement '
            'positif.',
      );
    }
    return parsed;
  }
}

/// Encodes and decodes the opaque cursors of the paginated routes.
abstract final class PageCursor {
  /// Encodes the sort key of the last item of a page.
  static String encode(String updatedAt, String id) {
    final String raw = jsonEncode(<String, String>{
      'updated_at': updatedAt,
      'id': id,
    });
    return base64Url.encode(utf8.encode(raw));
  }

  /// Decodes a cursor produced by [encode].
  ///
  /// Returns `null` when the cursor is not a cursor of this API.
  static PageCursorValue? decode(String? cursor) {
    if (cursor == null || cursor.isEmpty) return null;
    try {
      final String raw = utf8.decode(base64Url.decode(cursor));
      final Object? decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return null;
      final Object? updatedAt = decoded['updated_at'];
      final Object? id = decoded['id'];
      if (updatedAt is! String || id is! String) return null;
      return PageCursorValue(updatedAt: updatedAt, id: id);
    } on FormatException {
      return null;
    }
  }
}

/// The decoded content of an opaque cursor.
final class PageCursorValue {
  /// Creates a cursor value.
  const PageCursorValue({required this.updatedAt, required this.id});

  /// The sort key of the last item of the previous page.
  final String updatedAt;

  /// The identifier of the last item of the previous page.
  final String id;
}
