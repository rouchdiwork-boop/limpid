import '../model/import_format.dart';
import '../model/import_request.dart';
import 'parsed_document.dart';

/// Un lecteur de manuscrit d'un seul format.
///
/// Chaque format a son lecteur, dans son propre fichier : un DOCX et un ODT
/// n'ont rien en commun, et les confondre rendrait les corrections
/// impossibles.
abstract interface class ManuscriptReader {
  /// Le format que le lecteur sait lire.
  ImportFormat get format;

  /// Lit le contenu de [request] et rend ce qu'il contient.
  ///
  /// Leve une [ImportException] quand le fichier est illisible.
  ParsedDocument read(ImportRequest request);
}
