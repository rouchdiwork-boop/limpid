import 'package:limpid_core/limpid_core.dart';

/// The language of a manuscript the device does not know yet.
///
/// The local model does not carry the language of a book yet: the value is
/// the default of the server, so the two sides agree until the local model
/// grows the field. The constant is named, never written in place, so the
/// day the local model knows the language, the one place to change is
/// found.
const String defaultProjectLanguage = 'fr-FR';

/// The declaration of a local project, as the server must know it.
///
/// The declaration is what travels to the server when the project is
/// registered: the identifier, the title, the synopsis, the language and the
/// two states of the publication (D-33) — the editorial stage and the
/// visibility.
///
/// The object is immutable: the declaration of a project never changes
/// under the feet of the caller.
final class ProjectDeclaration {
  /// Creates a declaration.
  const ProjectDeclaration({
    required this.id,
    required this.title,
    required this.synopsis,
    required this.status,
    required this.isPublic,
    this.language = defaultProjectLanguage,
  });

  /// The identifier of the project on the device.
  ///
  /// The identifier is the one the local database knows. The server may
  /// mint another one: the registry then makes the device adopt it, so
  /// both sides end up with the same identifier.
  final String id;

  /// The title of the manuscript.
  final String title;

  /// The synopsis of the manuscript.
  final String synopsis;

  /// The editorial stage of the manuscript.
  final ManuscriptStatus status;

  /// Whether the book is in the showcase of the server.
  final bool isPublic;

  /// The language of the manuscript, as a BCP 47 tag.
  final String language;

  /// Returns a copy of this declaration with the given fields replaced.
  ProjectDeclaration copyWith({
    String? id,
    String? title,
    String? synopsis,
    ManuscriptStatus? status,
    bool? isPublic,
    String? language,
  }) {
    return ProjectDeclaration(
      id: id ?? this.id,
      title: title ?? this.title,
      synopsis: synopsis ?? this.synopsis,
      status: status ?? this.status,
      isPublic: isPublic ?? this.isPublic,
      language: language ?? this.language,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ProjectDeclaration &&
          other.id == id &&
          other.title == title &&
          other.synopsis == synopsis &&
          other.status == status &&
          other.isPublic == isPublic &&
          other.language == language);

  @override
  int get hashCode =>
      Object.hash(id, title, synopsis, status, isPublic, language);

  @override
  String toString() => 'ProjectDeclaration($id, $title, published: $isPublic)';
}
