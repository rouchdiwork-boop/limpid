import 'dart:convert';
import 'dart:typed_data';

import 'package:limpid_import/limpid_import.dart';
import 'package:test/test.dart';

/// Le carnet Markdown de la suite de tests.
const String carnet = r'''
---
title: Le carnet
---

# Première partie

Un paragraphe de présentation.

- un premier élément
- un second élément

## Premier chapitre

Le texte du premier chapitre.

> Une citation mémorable.

```dart
void main() {}
```

* * *

La suite de la scène.

## Second chapitre

Le texte du second chapitre.
''';

void main() {
  group('import Markdown', () {
    late ImportedManuscript manuscript;

    setUp(() async {
      manuscript = await const LimpidImporter().import(
        ImportRequest(
          fileName: 'carnet.md',
          bytes: Uint8List.fromList(utf8.encode(carnet)),
        ),
      );
    });

    test('lit le titre de l\'en-tete', () {
      expect(manuscript.title, 'Le carnet');
    });

    test('conserve les titres et leurs niveaux', () {
      expect(manuscript.chapterCount, 3);
      expect(
        manuscript.chapters.map((ImportedChapter chapter) => chapter.title),
        <String>['Première partie', 'Premier chapitre', 'Second chapitre'],
      );
      expect(
        manuscript.chapters.map((ImportedChapter chapter) => chapter.level),
        <int>[1, 2, 2],
      );
    });

    test('transforme une liste en plusieurs blocs', () {
      final ImportedChapter partie = manuscript.chapters.first;
      expect(partie.sceneCount, 1);
      final ImportedScene scene = partie.scenes.single;
      expect(scene.blockCount, 3);
      expect(scene.blocks[0].type, ImportedBlockType.paragraph);
      expect(scene.blocks[0].text, 'Un paragraphe de présentation.');
      expect(scene.blocks[1].type, ImportedBlockType.listItem);
      expect(scene.blocks[1].text, 'un premier élément');
      expect(scene.blocks[2].type, ImportedBlockType.listItem);
      expect(scene.blocks[2].text, 'un second élément');
    });

    test('coupe la scene au separateur horizontal', () {
      final ImportedChapter chapitre = manuscript.chapters[1];
      expect(chapitre.sceneCount, 2);
      expect(chapitre.scenes.first.blockCount, 3);
      expect(
        chapitre.scenes.first.blocks.map((ImportedBlock block) => block.type),
        <ImportedBlockType>[
          ImportedBlockType.paragraph,
          ImportedBlockType.quote,
          ImportedBlockType.code,
        ],
      );
      expect(chapitre.scenes.last.blocks.single.text, 'La suite de la scène.');
    });

    test('garde le langage d\'un bloc de code', () {
      final ImportedBlock code =
          manuscript.chapters[1].scenes.first.blocks.last;
      expect(code.type, ImportedBlockType.code);
      expect(code.language, 'dart');
      expect(code.text, 'void main() {}');
    });

    test('ne perd aucun mot', () {
      expect(manuscript.wordCount, greaterThan(20));
    });
  });
}
