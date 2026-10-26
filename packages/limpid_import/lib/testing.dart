/// Les fichiers d'essai du moteur d'import.
///
/// Cette bibliotheque construit de **vrais** fichiers : un DOCX, un ODT et
/// un EPUB sont des paquets ZIP que Word, LibreOffice et les lecteurs EPUB
/// ouvrent. Une fixture qui ne s'ouvre pas ne prouve rien.
///
/// ```dart
/// final ImportedManuscript manuscript = await const LimpidImporter().import(
///   ImportRequest(fileName: 'livre.docx', bytes: buildDocx()),
/// );
/// ```
library;

export 'src/testing/fixtures.dart';
