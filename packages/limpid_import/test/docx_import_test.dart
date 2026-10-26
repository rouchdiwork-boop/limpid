import 'dart:typed_data';

import 'package:limpid_import/limpid_import.dart';
import 'package:limpid_import/testing.dart';
import 'package:test/test.dart';

void main() {
  group('import DOCX', () {
    late ImportedManuscript manuscript;

    setUp(() async {
      manuscript = await const LimpidImporter().import(
        ImportRequest(fileName: 'livre.docx', bytes: buildDocx()),
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

    test('lit le texte des runs', () {
      expect(
        manuscript.chapters.first.scenes.single.blocks.single.text,
        'Un paragraphe.',
      );
    });

    test('transforme une liste en bloc de liste', () {
      final ImportedChapter chapitre = manuscript.chapters[1];
      final ImportedBlock item = chapitre.scenes.first.blocks.last;
      expect(item.type, ImportedBlockType.listItem);
      expect(item.text, 'Un element de liste');
      expect(item.isOrdered, isFalse);
    });

    test('coupe la scene au saut de page', () {
      final ImportedChapter chapitre = manuscript.chapters[1];
      expect(chapitre.sceneCount, 2);
      expect(chapitre.scenes.last.blocks.single.text, 'La suite de la scene.');
    });

    test('annonce les images laissees de cote', () {
      expect(manuscript.skipped, hasLength(1));
      expect(manuscript.skipped.single.reason, 'images');
      expect(manuscript.skipped.single.count, 1);
    });
  });

  group('import DOCX invalide', () {
    test('refuse un paquet sans corps', () async {
      final Uint8List bytes = buildZip(<MapEntry<String, List<int>>>[
        MapEntry<String, List<int>>('[Content_Types].xml', <int>[1, 2, 3]),
      ]);
      await expectLater(
        const LimpidImporter().import(
          ImportRequest(fileName: 'livre.docx', bytes: bytes),
        ),
        throwsA(isA<ImportException>()),
      );
    });
  });
}
