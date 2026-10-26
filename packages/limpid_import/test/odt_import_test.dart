import 'package:limpid_import/limpid_import.dart';
import 'package:limpid_import/testing.dart';
import 'package:test/test.dart';

void main() {
  group('import ODT', () {
    late ImportedManuscript manuscript;

    setUp(() async {
      manuscript = await const LimpidImporter().import(
        ImportRequest(fileName: 'livre.odt', bytes: buildOdt()),
      );
    });

    test('lit le titre du document', () {
      expect(manuscript.title, 'Le livre');
    });

    test('conserve les titres et leurs niveaux', () {
      expect(manuscript.chapterCount, 2);
      expect(
        manuscript.chapters.map((ImportedChapter chapter) => chapter.title),
        <String>['Le titre', 'Premier chapitre'],
      );
      expect(
        manuscript.chapters.map((ImportedChapter chapter) => chapter.level),
        <int>[1, 2],
      );
    });

    test('lit les paragraphes', () {
      expect(
        manuscript.chapters.first.scenes.single.blocks.single.text,
        'Un paragraphe.',
      );
    });

    test('transforme une liste en autant de blocs que d\'elements', () {
      final ImportedChapter chapitre = manuscript.chapters[1];
      final ImportedScene scene = chapitre.scenes.single;
      expect(scene.blockCount, 3);
      expect(scene.blocks[1].type, ImportedBlockType.listItem);
      expect(scene.blocks[1].text, 'Un element de liste');
      expect(scene.blocks[2].type, ImportedBlockType.listItem);
      expect(scene.blocks[2].text, 'Un autre element');
    });

    test('ne perd aucun mot', () {
      expect(manuscript.wordCount, greaterThan(10));
    });
  });
}
