import 'dart:convert';
import 'dart:typed_data';

import 'package:limpid_import/limpid_import.dart';
import 'package:test/test.dart';

/// Le carnet texte de la suite de tests.
const String carnet = '''
Le premier paragraphe.

Le deuxieme paragraphe, sur deux lignes
qui se continue.

Le troisieme paragraphe.
''';

void main() {
  group('import TXT', () {
    late ImportedManuscript manuscript;

    setUp(() async {
      manuscript = await const LimpidImporter().import(
        ImportRequest(
          fileName: 'carnet.txt',
          bytes: Uint8List.fromList(utf8.encode(carnet)),
        ),
      );
    });

    test('nomme le chapitre d\'apres le fichier', () {
      expect(manuscript.title, 'carnet');
      expect(manuscript.chapterCount, 1);
      expect(manuscript.chapters.single.title, 'carnet');
    });

    test('separe les scenes par les lignes vides', () {
      expect(manuscript.sceneCount, 3);
    });

    test('fait de chaque scene un seul bloc', () {
      final ImportedScene scene = manuscript.chapters.single.scenes.first;
      expect(scene.blockCount, 1);
      expect(scene.blocks.single.type, ImportedBlockType.paragraph);
      expect(scene.blocks.single.text, 'Le premier paragraphe.');
    });

    test('rejoint les lignes d\'un meme paragraphe', () {
      final ImportedScene scene = manuscript.chapters.single.scenes[1];
      expect(
        scene.blocks.single.text,
        'Le deuxieme paragraphe, sur deux lignes qui se continue.',
      );
    });
  });
}
