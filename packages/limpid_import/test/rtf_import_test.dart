import 'dart:convert';
import 'dart:typed_data';

import 'package:limpid_import/limpid_import.dart';
import 'package:test/test.dart';

/// Le carnet RTF de la suite de tests.
///
/// Le document porte une table des polices, un groupe d'information, un
/// titre de niveau 1, un paragraphe, un saut de page et un second
/// paragraphe.
const String carnet = r'''
{\rtf1\ansi\deff0
{\fonttbl{\f0 Times New Roman;}}
{\info{\title Le carnet RTF}}
\pard\outlinelevel1 La premiere partie\par
\pard Un paragraphe de presentation.\par
\pard\page
\pard Un paragraphe apres le saut de page.\par
}
''';

void main() {
  group('import RTF', () {
    late ImportedManuscript manuscript;

    setUp(() async {
      manuscript = await const LimpidImporter().import(
        ImportRequest(
          fileName: 'carnet.rtf',
          bytes: Uint8List.fromList(utf8.encode(carnet)),
        ),
      );
    });

    test('lit le titre du groupe d\'information', () {
      expect(manuscript.title, 'Le carnet RTF');
    });

    test('lit le titre de niveau 1 comme un chapitre', () {
      expect(manuscript.chapterCount, 1);
      final ImportedChapter chapitre = manuscript.chapters.single;
      expect(chapitre.title, 'La premiere partie');
      expect(chapitre.level, 1);
    });

    test('coupe la scene au saut de page', () {
      expect(manuscript.sceneCount, 2);
      expect(
        manuscript.chapters.single.scenes.first.blocks.single.text,
        'Un paragraphe de presentation.',
      );
      expect(
        manuscript.chapters.single.scenes.last.blocks.single.text,
        'Un paragraphe apres le saut de page.',
      );
    });

    test('ignore la table des polices', () {
      final String text = manuscript.chapters.single.scenes
          .expand((ImportedScene scene) => scene.blocks)
          .map((ImportedBlock block) => block.text)
          .join(' ');
      expect(text, isNot(contains('Times New Roman')));
    });
  });
}
