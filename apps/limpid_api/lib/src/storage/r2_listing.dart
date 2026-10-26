import 'stored_object.dart';

/// The answer of a listing of the objects of a bucket.
///
/// R2 speaks the S3 dialect : the listing is an XML document holding the
/// keys of a page of objects, their size, and the token of the next page
/// when the bucket holds more objects than the page.
///
/// The document is read with a scanner, not with a parser : the API has no
/// XML dependency, and the document is written by the bucket itself, never
/// by a user. Only the fields the purge and the storage measurement need
/// are read.
final class R2ObjectListing {
  /// Creates a listing.
  const R2ObjectListing({
    required this.objects,
    required this.isTruncated,
    this.continuationToken,
  });

  /// The objects of the page, with their size.
  final List<StoredObject> objects;

  /// The keys of the objects of the page.
  List<String> get keys =>
      objects.map((StoredObject object) => object.key).toList(growable: false);

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

  /// The size of an object.
  static final RegExp _size = RegExp(r'<Size>(.*?)</Size>', dotAll: true);

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
    final List<StoredObject> objects = <StoredObject>[];
    for (final RegExpMatch contents in _contents.allMatches(body)) {
      final String block = contents.group(0) ?? '';
      final RegExpMatch? key = _key.firstMatch(block);
      if (key == null) continue;
      objects.add(
        StoredObject(
          key: _unescape(key.group(1) ?? ''),
          sizeBytes: _sizeOf(block),
        ),
      );
    }
    final String? truncated = _truncated.firstMatch(body)?.group(1);
    final String? token = _token.firstMatch(body)?.group(1);
    return R2ObjectListing(
      objects: List<StoredObject>.unmodifiable(objects),
      isTruncated: truncated?.trim().toLowerCase() == 'true',
      continuationToken: token == null ? null : _unescape(token),
    );
  }

  /// The size of the object described by [block], in bytes.
  ///
  /// The dialect S3 carries the size of every object of the listing: the
  /// measurement of a storage therefore costs no read at all. A listing
  /// that does not carry it announces an empty size.
  static int _sizeOf(String block) {
    final String? raw = _size.firstMatch(block)?.group(1);
    return int.tryParse(raw?.trim() ?? '') ?? 0;
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
