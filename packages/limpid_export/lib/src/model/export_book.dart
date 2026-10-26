import 'export_chapter.dart';
import 'export_image.dart';
import 'export_metadata.dart';

/// Livre complet, pret a etre exporte.
///
/// C'est l'unite d'entree du moteur d'export. Elle est independante du
/// moteur CRDT de `limpid_core` : l'application se charge de la traduire
/// depuis son modele interne.
class ExportBook {
  /// Cree un livre exportable.
  ExportBook({
    required this.title,
    required this.chapters,
    this.subtitle,
    this.authors = const <String>[],
    this.language = 'fr-FR',
    this.metadata = const ExportMetadata(),
    this.coverImage,
  }) : assert(chapters.isNotEmpty, 'Un livre doit avoir au moins un chapitre.');

  /// Titre de l'ouvrage.
  final String title;

  /// Sous-titre, facultatif.
  final String? subtitle;

  /// Auteurs, dans l'ordre de credit.
  final List<String> authors;

  /// Langue de l'ouvrage (BCP 47).
  final String language;

  /// Metadonnees bibliographiques.
  final ExportMetadata metadata;

  /// Couverture, facultative.
  final ExportImage? coverImage;

  /// Chapitres du livre, dans l'ordre de lecture.
  final List<ExportChapter> chapters;

  /// Nombre de mots estime (somme des mots des blocs textuels).
  int get wordCount {
    var total = 0;
    for (final chapter in chapters) {
      for (final block in chapter.blocks) {
        if (!block.type.isTextual) {
          continue;
        }
        final trimmed = block.text.trim();
        if (trimmed.isEmpty) {
          continue;
        }
        total += trimmed.split(RegExp(r'\s+')).length;
      }
    }
    return total;
  }

  /// Copie immuable du livre.
  ExportBook copyWith({
    String? title,
    String? subtitle,
    List<String>? authors,
    String? language,
    ExportMetadata? metadata,
    ExportImage? coverImage,
    List<ExportChapter>? chapters,
  }) {
    return ExportBook(
      title: title ?? this.title,
      subtitle: subtitle ?? this.subtitle,
      authors: authors ?? this.authors,
      language: language ?? this.language,
      metadata: metadata ?? this.metadata,
      coverImage: coverImage ?? this.coverImage,
      chapters: chapters ?? this.chapters,
    );
  }

  @override
  String toString() => 'ExportBook($title, ${chapters.length} chapitres)';
}
