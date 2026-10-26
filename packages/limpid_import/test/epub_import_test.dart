import 'package:limpid_import/limpid_import.dart';
import 'package:limpid_import/testing.dart';
import 'package:test/test.dart';

void main() {
  group('import EPUB', () {
    late ImportedManuscript manuscript;

    setUp(() async {
      manuscript = await const LimpidImporter().import(
        ImportRequest(fileName: 'livre.epub', bytes: buildEpub()),
      );
    });

    test('lit le titre du livre', () {
      expect(manuscript.title, 'Le livre');
    });

    test('fait un chapitre par document de la spine', () {
      expect(manuscript.chapterCount, 2);
      expect(
        manuscript.chapters.map((ImportedChapter chapter) => chapter.title),
        <String>['Premier chapitre', 'Second chapitre'],
      );
    });

    test('ignore le document de navigation', () {
      expect(
        manuscript.chapters.map((ImportedChapter chapter) => chapter.title),
        isNot(contains('Table des matieres')),
      );
    });

    test('separe les scenes aux titres internes', () {
      final ImportedChapter chapitre = manuscript.chapters.first;
      expect(chapitre.sceneCount, 2);
      expect(chapitre.scenes.first.title, 'Une section');
      expect(
        chapitre.scenes.first.blocks.single.text,
        'Le texte de la section.',
      );
      expect(chapitre.scenes.last.title, 'Une sous-section');
      expect(chapitre.scenes.last.blockCount, 2);
    });

    test('transforme une liste en bloc de liste', () {
      final ImportedBlock item =
          manuscript.chapters.first.scenes.last.blocks.last;
      expect(item.type, ImportedBlockType.listItem);
      expect(item.text, 'Un element de liste');
    });

    test('annonce les images laissees de cote', () {
      expect(manuscript.skipped, hasLength(1));
      expect(manuscript.skipped.single.reason, 'images');
      expect(manuscript.skipped.single.count, 1);
    });
  });
}
