/// Metadonnees bibliographiques d'un livre exportable.
class ExportMetadata {
  /// Cree un ensemble de metadonnees.
  const ExportMetadata({
    this.isbn,
    this.description,
    this.publisher,
    this.rights,
    this.publicationDate,
    this.bisac = const <String>[],
    this.subjects = const <String>[],
    this.language,
    this.identifier,
  });

  /// ISBN (13 chiffres, avec ou sans tirets).
  final String? isbn;

  /// Resume de l'ouvrage.
  final String? description;

  /// Editeur.
  final String? publisher;

  /// Droits d'auteur (mention legale).
  final String? rights;

  /// Date de publication.
  final DateTime? publicationDate;

  /// Codes BISAC (categories de vente Amazon).
  final List<String> bisac;

  /// Subjects libres.
  final List<String> subjects;

  /// Langue de publication (BCP 47, par exemple `fr-FR`).
  final String? language;

  /// Identifiant interne de l'ouvrage, reutilise si aucun ISBN n'est fourni.
  final String? identifier;

  /// Copie immuable des metadonnees.
  ExportMetadata copyWith({
    String? isbn,
    String? description,
    String? publisher,
    String? rights,
    DateTime? publicationDate,
    List<String>? bisac,
    List<String>? subjects,
    String? language,
    String? identifier,
  }) {
    return ExportMetadata(
      isbn: isbn ?? this.isbn,
      description: description ?? this.description,
      publisher: publisher ?? this.publisher,
      rights: rights ?? this.rights,
      publicationDate: publicationDate ?? this.publicationDate,
      bisac: bisac ?? this.bisac,
      subjects: subjects ?? this.subjects,
      language: language ?? this.language,
      identifier: identifier ?? this.identifier,
    );
  }

  @override
  String toString() =>
      'ExportMetadata(isbn: $isbn, subjects: ${subjects.length})';
}
