import 'format_detector.dart';
import 'model/import_chapter.dart';
import 'model/import_exception.dart';
import 'model/import_format.dart';
import 'model/import_manuscript.dart';
import 'model/import_request.dart';
import 'model/import_skip.dart';
import 'reader_factory.dart';
import 'readers/manuscript_reader.dart';
import 'readers/parsed_document.dart';

/// Le point d'entree du moteur d'import.
///
/// L'interface est la seule que l'API connaisse : elle ne sait ni comment
/// un DOCX est lu, ni comment une liste Markdown devient plusieurs blocs.
abstract interface class ManuscriptImporter {
  /// Les formats que l'importateur sait lire.
  Set<ImportFormat> get formats;

  /// Lit [request] et rend le manuscrit qu'il contient.
  ///
  /// Leve une [ImportException] quand le format est inconnu ou quand le
  /// fichier est illisible.
  Future<ImportedManuscript> import(ImportRequest request);
}

/// L'importateur par defaut.
///
/// Il reconnait le format, choisit le lecteur, et rend une hierarchie de
/// chapitres, de scenes et de blocs.
final class LimpidImporter implements ManuscriptImporter {
  /// Cree un importateur.
  const LimpidImporter();

  /// Le titre donne a un manuscrit sans titre.
  static const String fallbackTitle = 'Manuscrit';

  @override
  Set<ImportFormat> get formats => ImportFormat.values.toSet();

  @override
  Future<ImportedManuscript> import(ImportRequest request) async {
    final ImportFormat? format = ImportFormatDetector.detect(request);
    if (format == null) {
      throw const ImportException(
        ImportErrorCodes.unsupportedFormat,
        "Le format du fichier n'est pas reconnu. Formats acceptes : "
        'docx, odt, epub, rtf, md, txt.',
      );
    }

    final ManuscriptReader reader = ManuscriptReaders.of(format);
    final ParsedDocument parsed = reader.read(request);
    return _toManuscript(request, parsed);
  }

  ImportedManuscript _toManuscript(
    ImportRequest request,
    ParsedDocument parsed,
  ) {
    final String title = _titleOf(parsed, request);
    final List<ImportedChapter> chapters = <ImportedChapter>[];
    for (var index = 0; index < parsed.chapters.length; index++) {
      final ImportedChapter chapter = parsed.chapters[index];
      chapters.add(
        chapter.title.isEmpty
            ? chapter.copyWith(title: 'Chapitre ${index + 1}')
            : chapter,
      );
    }
    return ImportedManuscript(
      title: title,
      chapters: List<ImportedChapter>.unmodifiable(chapters),
      skipped: List<ImportSkip>.unmodifiable(parsed.skipped),
    );
  }

  String _titleOf(ParsedDocument parsed, ImportRequest request) {
    final String declared = parsed.title?.trim() ?? '';
    if (declared.isNotEmpty) return declared;
    final String base = request.baseName;
    if (base.isNotEmpty) return base;
    return fallbackTitle;
  }
}
