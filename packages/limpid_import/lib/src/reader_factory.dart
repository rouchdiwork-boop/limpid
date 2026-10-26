import 'model/import_format.dart';
import 'readers/docx_reader.dart';
import 'readers/epub_reader.dart';
import 'readers/manuscript_reader.dart';
import 'readers/markdown_reader.dart';
import 'readers/odt_reader.dart';
import 'readers/rtf_reader.dart';
import 'readers/txt_reader.dart';

/// Le choix du lecteur d'apres le format.
///
/// Un seul endroit sait quel lecteur lit quel format : ajouter un format ne
/// demande qu'une ligne ici et un lecteur de plus.
abstract final class ManuscriptReaders {
  /// Le lecteur qui lit [format].
  static ManuscriptReader of(ImportFormat format) => switch (format) {
    ImportFormat.docx => const DocxReader(),
    ImportFormat.odt => const OdtReader(),
    ImportFormat.epub => const EpubReader(),
    ImportFormat.rtf => const RtfReader(),
    ImportFormat.markdown => const MarkdownReader(),
    ImportFormat.txt => const TxtReader(),
  };

  /// Tous les lecteurs, un par format.
  static List<ManuscriptReader> all() =>
      ImportFormat.values.map(ManuscriptReaders.of).toList(growable: false);
}
