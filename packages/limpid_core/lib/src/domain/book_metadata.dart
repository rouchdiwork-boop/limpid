import 'package:limpid_core/src/internal/collections.dart';

import 'ids.dart';

/// Publication metadata of a book (B3).
final class BookMetadata {
  /// Creates book metadata.
  const BookMetadata({
    required this.id,
    required this.title,
    this.subtitle = '',
    this.isbn = '',
    this.isbn13 = '',
    this.bisacCodes = const <String>[],
    this.language = 'fr-FR',
    this.publisher = '',
    this.copyright = '',
    this.contributors = const <String>[],
    this.description = '',
    this.keywords = const <String>[],
    this.publicationDate,
    this.ageRating = '',
    this.createdAt,
    this.updatedAt,
  });

  /// Identifier of the metadata set.
  final ProjectId id;

  /// Title of the book.
  final String title;

  /// Subtitle of the book.
  final String subtitle;

  /// ISBN-10 of the book.
  final String isbn;

  /// ISBN-13 of the book.
  final String isbn13;

  /// BISAC classification codes.
  final List<String> bisacCodes;

  /// BCP-47 language tag of the book.
  final String language;

  /// Publisher name.
  final String publisher;

  /// Copyright notice.
  final String copyright;

  /// Contributors (co-authors, translators, editors…).
  final List<String> contributors;

  /// Public description of the book.
  final String description;

  /// Search keywords.
  final List<String> keywords;

  /// Publication date.
  final DateTime? publicationDate;

  /// Age rating label.
  final String ageRating;

  /// Creation timestamp.
  final DateTime? createdAt;

  /// Last modification timestamp.
  final DateTime? updatedAt;

  /// Whether the book carries a usable ISBN.
  bool get hasIsbn => isbn.isNotEmpty || isbn13.isNotEmpty;

  /// Returns a copy of this metadata with the given fields replaced.
  BookMetadata copyWith({
    String? title,
    String? subtitle,
    String? isbn,
    String? isbn13,
    List<String>? bisacCodes,
    String? language,
    String? publisher,
    String? copyright,
    List<String>? contributors,
    String? description,
    List<String>? keywords,
    DateTime? publicationDate,
    String? ageRating,
    DateTime? updatedAt,
  }) {
    return BookMetadata(
      id: id,
      title: title ?? this.title,
      subtitle: subtitle ?? this.subtitle,
      isbn: isbn ?? this.isbn,
      isbn13: isbn13 ?? this.isbn13,
      bisacCodes: bisacCodes ?? this.bisacCodes,
      language: language ?? this.language,
      publisher: publisher ?? this.publisher,
      copyright: copyright ?? this.copyright,
      contributors: contributors ?? this.contributors,
      description: description ?? this.description,
      keywords: keywords ?? this.keywords,
      publicationDate: publicationDate ?? this.publicationDate,
      ageRating: ageRating ?? this.ageRating,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is BookMetadata &&
          other.id == id &&
          other.title == title &&
          other.subtitle == subtitle &&
          other.isbn == isbn &&
          other.isbn13 == isbn13 &&
          other.language == language &&
          other.publisher == publisher &&
          other.copyright == copyright &&
          other.description == description &&
          other.ageRating == ageRating &&
          other.publicationDate == publicationDate &&
          other.createdAt == createdAt &&
          other.updatedAt == updatedAt &&
          listEquals(other.bisacCodes, bisacCodes) &&
          listEquals(other.contributors, contributors) &&
          listEquals(other.keywords, keywords));

  @override
  int get hashCode => Object.hash(
    BookMetadata,
    id,
    title,
    subtitle,
    isbn,
    isbn13,
    language,
    publisher,
    copyright,
    description,
    ageRating,
    publicationDate,
    createdAt,
    updatedAt,
    Object.hashAll(bisacCodes),
    Object.hashAll(contributors),
    Object.hashAll(keywords),
  );

  @override
  String toString() => 'BookMetadata($id, $title)';
}
