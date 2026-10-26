/// The answer of a listing of the objects of a bucket.
///
/// R2 speaks the S3 dialect : the listing is an XML document holding the
/// keys of a page of objects, and the token of the next page when the bucket
/// holds more objects than the page.
///
/// The document is read with a scanner, not with a parser : the API has no
/// XML dependency, and the document is written by the bucket itself, never
/// by a user. Only the four fields the purge needs are read.
final class R2ObjectListing {
  /// Creates a listing.
  const R2ObjectListing({
    required this.keys,
    required this.isTruncated,
    this.continuationToken,
  });

  /// The keys of the objects of the page.
  final List<String> keys;

  /// Whether the bucket holds more objects than the page.
  final bool isTruncated;

  /// The token of the next page, `null` when the listing is complete.
  final String? continuationToken;

  /// The contents of the objects of the page.
  static final RegExp _contents = RegExp(
    r'<Contents>(.*?)</Contents>',
    dotAll: true,
  );

  /// The key of an object.
  static final RegExp _key = RegExp(r'<Key>(.*?)</Key>', dotAll: true);

  /// The flag telling whether the listing is truncated.
  static final RegExp _truncated = RegExp(
    r'<IsTruncated>(.*?)</IsTruncated>',
    dotAll: true,
  );

  /// The token of the next page.
  static final RegExp _token = RegExp(
    r'<NextContinuationToken>(.*?)</NextContinuationToken>',
    dotAll: true,
  );

  /// Reads the XML answer of a listing.
  ///
  /// A document that carries no object answers an empty listing: the bucket
  /// is simply empty under that prefix.
  static R2ObjectListing parse(String body) {
    final List<String> keys = <String>[];
    for (final RegExpMatch contents in _contents.allMatches(body)) {
      final RegExpMatch? key = _key.firstMatch(contents.group(0) ?? '');
      if (key != null) keys.add(_unescape(key.group(1) ?? ''));
    }
    final String? truncated = _truncated.firstMatch(body)?.group(1);
    final String? token = _token.firstMatch(body)?.group(1);
    return R2ObjectListing(
      keys: List<String>.unmodifiable(keys),
      isTruncated: truncated?.trim().toLowerCase() == 'true',
      continuationToken: token == null ? null : _unescape(token),
    );
  }

  /// Reads the escaped characters of a value written by the bucket.
  static String _unescape(String value) {
    return value
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll('&apos;', "'")
        .replaceAll('&amp;', '&');
  }
}
