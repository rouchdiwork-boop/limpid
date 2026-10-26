import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_quill/quill_delta.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:limpid_design_system/limpid_design_system.dart';
import 'package:limpid_quill/limpid_quill.dart';

import 'test_helpers.dart';

const SceneId _scene = SceneId('scene-1');
const AuthorId _author = AuthorId('auteur-1');

QuillController _emptyController() {
  return QuillController(
    document: Document.fromDelta(Delta()..insert('\n')),
    selection: const TextSelection.collapsed(offset: 0),
  );
}

void main() {
  testWidgets('la scène affiche le texte saisi', (tester) async {
    final QuillController controller = _emptyController();

    await tester.pumpWidget(
      limpidTestApp(
        child: LimpidSceneEditor(
          sceneId: _scene,
          authorId: _author,
          controller: controller,
        ),
      ),
    );
    await tester.pump();

    controller.replaceText(
      0,
      0,
      'Bonjour',
      const TextSelection.collapsed(offset: 7),
    );
    await tester.pump();

    expect(findRichTextContaining('Bonjour'), findsOneWidget);
  });

  testWidgets('la scène annonce chaque changement', (tester) async {
    final QuillController controller = _emptyController();
    final List<List<SyncOp>> changes = <List<SyncOp>>[];

    await tester.pumpWidget(
      limpidTestApp(
        child: LimpidSceneEditor(
          sceneId: _scene,
          authorId: _author,
          controller: controller,
          onChanged: changes.add,
        ),
      ),
    );
    await tester.pump();

    controller.replaceText(
      0,
      0,
      'Bonjour',
      const TextSelection.collapsed(offset: 7),
    );
    await tester.pump();

    expect(changes, hasLength(1));
    expect(changes.single, hasLength(1));
    expect(changes.single.single, isA<UpdateContentOp>());
    expect(changes.single.single.kind, 'updateContent');
  });

  testWidgets('une scène vide écrit son premier bloc', (tester) async {
    // La scène ne porte encore aucun bloc : la premiere frappe doit
    // **insérer** un bloc. Une mise a jour viserait un bloc que le
    // document CRDT ne connait pas, et le texte disparaitrait.
    final QuillController controller = _emptyController();
    final List<List<SyncOp>> changes = <List<SyncOp>>[];

    await tester.pumpWidget(
      limpidTestApp(
        child: LimpidSceneEditor(
          sceneId: _scene,
          authorId: _author,
          controller: controller,
          initialBlocks: const <SceneBlock>[],
          onChanged: changes.add,
        ),
      ),
    );
    await tester.pump();

    controller.replaceText(
      0,
      0,
      'Bonjour',
      const TextSelection.collapsed(offset: 7),
    );
    await tester.pump();

    expect(changes, hasLength(1));
    expect(changes.single, hasLength(1));
    expect(changes.single.single, isA<InsertBlockOp>());
    expect(changes.single.single.kind, 'insertBlock');
  });

  testWidgets('la scène monte dans les quatre thèmes', (tester) async {
    for (final LimpidThemeVariant variant in LimpidThemeVariant.values) {
      await tester.pumpWidget(
        limpidTestApp(
          variant: variant,
          child: LimpidSceneEditor(
            sceneId: _scene,
            authorId: _author,
            controller: _emptyController(),
          ),
        ),
      );
      await tester.pump();

      expect(find.byType(LimpidSceneEditor), findsOneWidget);
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('le mode lecture seule empêche la saisie', (tester) async {
    final QuillController controller = _emptyController();

    await tester.pumpWidget(
      limpidTestApp(
        child: LimpidSceneEditor(
          sceneId: _scene,
          authorId: _author,
          controller: controller,
          readOnly: true,
        ),
      ),
    );
    await tester.pump();

    expect(controller.readOnly, isTrue);
  });

  testWidgets('le mode focus atténue les paragraphes inactifs', (tester) async {
    final QuillController controller = QuillController(
      document: Document.fromDelta(
        Delta()
          ..insert('Premier\n')
          ..insert('Second\n'),
      ),
      selection: const TextSelection.collapsed(offset: 0),
    );

    await tester.pumpWidget(
      limpidTestApp(
        child: LimpidSceneEditor(
          sceneId: _scene,
          authorId: _author,
          controller: controller,
          mode: LimpidSceneEditorMode.focus,
        ),
      ),
    );
    await tester.pump();

    final Iterable<RichText> texts = tester
        .widgetList<RichText>(find.byType(RichText))
        .where((RichText text) => text.text.toPlainText().contains('Second'));
    expect(texts, isNotEmpty);
  });
}
