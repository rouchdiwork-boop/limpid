import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_quill/quill_delta.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:limpid_quill/limpid_quill.dart';

import 'test_helpers.dart';

const SceneId _scene = SceneId('scene-1');
const AuthorId _author = AuthorId('auteur-1');

void main() {
  group('Catalogue du menu slash', () {
    test('il propose les blocs et les commandes IA', () {
      final List<LimpidSlashMenuItem> items = buildDefaultSlashMenuItems();

      expect(
        items.where(
          (LimpidSlashMenuItem item) =>
              item.kind == LimpidSlashMenuItemKind.block,
        ),
        hasLength(9),
      );
      expect(
        items.where(
          (LimpidSlashMenuItem item) => item.kind == LimpidSlashMenuItemKind.ai,
        ),
        hasLength(4),
      );
      expect(
        items.any(
          (LimpidSlashMenuItem item) => item.blockType == BlockType.image,
        ),
        isTrue,
      );
      expect(
        items.any(
          (LimpidSlashMenuItem item) => item.blockType == BlockType.sceneBreak,
        ),
        isTrue,
      );
    });
  });

  group('Contrôleur du menu slash', () {
    test('il filtre les entrées sur la saisie', () {
      final LimpidSlashMenuController controller = LimpidSlashMenuController();

      controller.open(query: 'tit');

      expect(controller.items, isNotEmpty);
      expect(
        controller.items.every(
          (LimpidSlashMenuItem item) =>
              item.label.toLowerCase().contains('tit'),
        ),
        isTrue,
      );
    });

    test('il navigue avec les flèches', () {
      final LimpidSlashMenuController controller = LimpidSlashMenuController();

      controller.open();
      expect(controller.selectedIndex, 0);

      controller.moveSelection(1);
      expect(controller.selectedIndex, 1);

      controller.moveSelection(-1);
      expect(controller.selectedIndex, 0);

      controller.moveSelection(-1);
      expect(controller.selectedIndex, controller.items.length - 1);
    });

    test('il se ferme sur Échap', () {
      final LimpidSlashMenuController controller = LimpidSlashMenuController();
      controller.open();

      final bool handled = controller.handleKeyEvent(
        const KeyDownEvent(
          logicalKey: LogicalKeyboardKey.escape,
          physicalKey: PhysicalKeyboardKey.escape,
          timeStamp: Duration.zero,
        ),
      );

      expect(handled, isTrue);
      expect(controller.isOpen, isFalse);
    });

    test('il choisit l’entrée sélectionnée sur Entrée', () {
      final LimpidSlashMenuController controller = LimpidSlashMenuController();
      LimpidSlashMenuItem? chosen;
      controller.onSelected = (LimpidSlashMenuItem item) => chosen = item;
      controller.open();

      final bool handled = controller.handleKeyEvent(
        const KeyDownEvent(
          logicalKey: LogicalKeyboardKey.enter,
          physicalKey: PhysicalKeyboardKey.enter,
          timeStamp: Duration.zero,
        ),
      );

      expect(handled, isTrue);
      expect(chosen, isNotNull);
      expect(chosen!.id, 'block.paragraph');
    });
  });

  group('Menu slash dans l’éditeur', () {
    testWidgets('il s’ouvre sur la barre oblique', (tester) async {
      final QuillController controller = QuillController(
        document: Document.fromDelta(Delta()..insert('\n')),
        selection: const TextSelection.collapsed(offset: 0),
      );
      final FocusNode focusNode = FocusNode();

      await tester.pumpWidget(
        limpidTestApp(
          child: LimpidSceneEditor(
            sceneId: _scene,
            authorId: _author,
            controller: controller,
            focusNode: focusNode,
          ),
        ),
      );
      await tester.pump();

      controller.replaceText(
        0,
        0,
        '/',
        const TextSelection.collapsed(offset: 1),
      );
      await tester.pump();

      expect(find.byType(LimpidSlashMenu), findsOneWidget);
      expect(find.text('Paragraphe'), findsOneWidget);
    });

    testWidgets('il se ferme sur Échap', (tester) async {
      final QuillController controller = QuillController(
        document: Document.fromDelta(Delta()..insert('\n')),
        selection: const TextSelection.collapsed(offset: 0),
      );
      final FocusNode focusNode = FocusNode();

      await tester.pumpWidget(
        limpidTestApp(
          child: LimpidSceneEditor(
            sceneId: _scene,
            authorId: _author,
            controller: controller,
            focusNode: focusNode,
          ),
        ),
      );
      await tester.pump();
      focusNode.requestFocus();
      await tester.pump();

      controller.replaceText(
        0,
        0,
        '/',
        const TextSelection.collapsed(offset: 1),
      );
      await tester.pump();
      expect(find.byType(LimpidSlashMenu), findsOneWidget);

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();

      expect(find.byType(LimpidSlashMenu), findsNothing);
    });

    testWidgets('il navigue au clavier', (tester) async {
      final QuillController controller = QuillController(
        document: Document.fromDelta(Delta()..insert('\n')),
        selection: const TextSelection.collapsed(offset: 0),
      );
      final FocusNode focusNode = FocusNode();
      final LimpidSlashMenuController slash = LimpidSlashMenuController();

      await tester.pumpWidget(
        limpidTestApp(
          child: LimpidSceneEditor(
            sceneId: _scene,
            authorId: _author,
            controller: controller,
            focusNode: focusNode,
            slashMenuController: slash,
          ),
        ),
      );
      await tester.pump();
      focusNode.requestFocus();
      await tester.pump();

      controller.replaceText(
        0,
        0,
        '/',
        const TextSelection.collapsed(offset: 1),
      );
      await tester.pump();
      expect(slash.isOpen, isTrue);
      expect(slash.selectedIndex, 0);

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      expect(slash.selectedIndex, 1);

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.pump();
      expect(slash.selectedIndex, 0);
    });

    testWidgets('il applique le bloc choisi', (tester) async {
      final QuillController controller = QuillController(
        document: Document.fromDelta(Delta()..insert('\n')),
        selection: const TextSelection.collapsed(offset: 0),
      );
      final FocusNode focusNode = FocusNode();

      await tester.pumpWidget(
        limpidTestApp(
          child: LimpidSceneEditor(
            sceneId: _scene,
            authorId: _author,
            controller: controller,
            focusNode: focusNode,
          ),
        ),
      );
      await tester.pump();
      focusNode.requestFocus();
      await tester.pump();

      controller.replaceText(
        0,
        0,
        '/',
        const TextSelection.collapsed(offset: 1),
      );
      await tester.pump();
      expect(find.byType(LimpidSlashMenu), findsOneWidget);

      await tester.tap(find.text('Titre 1'));
      await tester.pump();

      expect(find.byType(LimpidSlashMenu), findsNothing);
      final List<Map<String, dynamic>> json = controller.document
          .toDelta()
          .toJson();
      expect(json.first['attributes'], containsPair('header', 1));
    });
  });
}
