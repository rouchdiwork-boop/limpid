import '../model/import_block.dart';
import '../model/import_format.dart';
import '../model/import_request.dart';
import 'chapter_builder.dart';
import 'manuscript_reader.dart';
import 'parsed_document.dart';
import 'text_decoding.dart';

/// Le lecteur de fichier texte brut.
///
/// Un fichier texte ne porte ni style ni titre : il tient en un seul
/// chapitre. Les lignes vides separent les scenes, et le texte d'une scene
/// tient en un seul bloc : l'import ne fabrique pas une structure que le
/// fichier ne contient pas.
final class TxtReader implements ManuscriptReader {
  /// Cree un lecteur de texte brut.
  const TxtReader();

  @override
  ImportFormat get format => ImportFormat.txt;

  @override
  ParsedDocument read(ImportRequest request) {
    final String text = decodeText(request.bytes);
    final ChapterBuilder builder = ChapterBuilder(
      defaultTitle: request.baseName,
    );
    builder.openChapter(request.baseName);

    final List<String> paragraph = <String>[];
    for (final String line in text.split('\n')) {
      if (line.trim().isEmpty) {
        _flush(paragraph, builder);
        continue;
      }
      paragraph.add(line.trim());
    }
    _flush(paragraph, builder);

    return builder.build(title: request.baseName);
  }

  static void _flush(List<String> paragraph, ChapterBuilder builder) {
    if (paragraph.isEmpty) return;
    final String content = paragraph.join(' ').trim();
    paragraph.clear();
    if (content.isEmpty) return;
    builder.breakScene();
    builder.addBlock(
      ImportedBlock(type: ImportedBlockType.paragraph, text: content),
    );
  }
}
