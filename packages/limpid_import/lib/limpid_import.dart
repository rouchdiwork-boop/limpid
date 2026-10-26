/// Moteur d'import de manuscrits de Limpid.
///
/// Six formats sont lus : DOCX, ODT, EPUB, RTF, Markdown et TXT. Tous
/// rendent la meme chose : une hierarchie de chapitres, de scenes et de
/// blocs. Un import ne fait jamais un seul bloc, et il n'invente pas ce que
/// le fichier ne porte pas.
///
/// ```dart
/// final ImportedManuscript manuscript = await const LimpidImporter().import(
///   ImportRequest(fileName: 'livre.docx', bytes: bytes),
/// );
/// ```
///
/// Le paquet ne depend que du SDK et des deux bibliotheques deja presentes
/// dans l'arbre du monorepo : `archive` pour les paquets ZIP, `xml` pour
/// les documents XML.
library;

export 'src/format_detector.dart';
export 'src/importer.dart';
export 'src/model/import_block.dart';
export 'src/model/import_chapter.dart';
export 'src/model/import_exception.dart';
export 'src/model/import_format.dart';
export 'src/model/import_manuscript.dart';
export 'src/model/import_request.dart';
export 'src/model/import_scene.dart';
export 'src/model/import_skip.dart';
export 'src/reader_factory.dart';
export 'src/readers/chapter_builder.dart';
export 'src/readers/docx_reader.dart';
export 'src/readers/epub_reader.dart';
export 'src/readers/manuscript_reader.dart';
export 'src/readers/markdown_reader.dart';
export 'src/readers/odt_reader.dart';
export 'src/readers/parsed_document.dart';
export 'src/readers/rtf_reader.dart';
export 'src/readers/txt_reader.dart';
export 'src/readers/zip_package.dart';
