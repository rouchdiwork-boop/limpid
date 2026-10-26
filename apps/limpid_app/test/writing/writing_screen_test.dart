import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:limpid_app/l10n/generated/app_localizations.dart';
import 'package:limpid_app/src/domain/providers.dart';
import 'package:limpid_app/src/domain/repositories.dart';
import 'package:limpid_app/src/features/writing/widgets/writing_outline_panel.dart';
import 'package:limpid_app/src/features/writing/widgets/writing_toolbar.dart';
import 'package:limpid_app/src/features/writing/writing_screen.dart';
import 'package:limpid_core/limpid_core.dart';
import 'package:limpid_design_system/limpid_design_system.dart';
import 'package:limpid_quill/limpid_quill.dart';

import '../editor/fakes.dart';

/// The identifier of the project used by the tests.
const String _projectId = 'projet-1';

/// The identifier of the scene opened first.
const String _firstSceneId = 'scene-1';

/// The identifier of the document of the first scene.
const String _firstDocumentId = 'scene-1-document';

/// Gives the test a viewport large enough for the desktop layout.
void useSurface(WidgetTester tester, Size size) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

/// Flushes the microtasks and the frames the screen needs.
Future<void> settle(WidgetTester tester) async {
  for (int frame = 0; frame < 5; frame++) {
    await tester.pump(const Duration(milliseconds: 20));
  }
}

/// Builds the repository of the tests: two chapters, three scenes.
FakeManuscriptRepository buildRepository() {
  final Chapter firstChapter = Chapter(
    id: const ChapterId('chapitre-1'),
    title: 'Le sel',
    order: OrderKey('1'),
  );
  final Chapter secondChapter = Chapter(
    id: const ChapterId('chapitre-2'),
    title: 'La cloche de Saint-Mérien',
    order: OrderKey('2'),
  );
  final Scene firstScene = Scene(
    id: const SceneId('scene-1'),
    chapterId: const ChapterId('chapitre-1'),
    documentId: const DocumentId('scene-1-document'),
    title: 'La plage à marée basse',
    order: OrderKey('1'),
    wordCount: 3,
  );
  final Scene secondScene = Scene(
    id: const SceneId('scene-2'),
    chapterId: const ChapterId('chapitre-1'),
    documentId: const DocumentId('scene-2-document'),
    title: 'Ce que le comptoir bavarde',
    order: OrderKey('2'),
    wordCount: 12,
  );
  final Scene thirdScene = Scene(
    id: const SceneId('scene-3'),
    chapterId: const ChapterId('chapitre-2'),
    documentId: const DocumentId('scene-3-document'),
    title: 'Le cycle de douze minutes',
    order: OrderKey('1'),
    wordCount: 640,
  );

  return FakeManuscriptRepository(
    chapters: <Chapter>[firstChapter, secondChapter],
    scenes: <String, List<Scene>>{
      'chapitre-1': <Scene>[firstScene, secondScene],
      'chapitre-2': <Scene>[thirdScene],
    },
    documents: <String, CrdtDocument>{
      'scene-1-document': fakeDocument(
        documentId: 'scene-1-document',
        text: 'Bonjour le monde',
      ),
      'scene-2-document': fakeDocument(
        documentId: 'scene-2-document',
        text: 'Le comptoir bavarde toute la journée.',
      ),
    },
  );
}

/// Wraps the screen in a provider scope holding the fakes.
Widget harness(
  Widget child, {
  required FakeManuscriptRepository manuscript,
  required FakeSyncRepository sync,
  required FakeAiRepository ai,
}) {
  return ProviderScope(
    overrides: [
      manuscriptRepositoryProvider.overrideWithValue(manuscript),
      syncRepositoryProvider.overrideWithValue(sync),
      aiRepositoryProvider.overrideWithValue(ai),
    ],
    child: MaterialApp(
      theme: LimpidTheme.of(LimpidThemeVariant.paper),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: child),
    ),
  );
}

void main() {
  late FakeManuscriptRepository manuscript;
  late FakeSyncRepository sync;
  late FakeAiRepository ai;

  setUp(() {
    manuscript = buildRepository();
    sync = FakeSyncRepository();
    ai = FakeAiRepository();
  });

  tearDown(() async {
    await sync.close();
  });

  Future<void> pumpScreen(WidgetTester tester) async {
    await tester.pumpWidget(
      harness(
        const WritingScreen(projectId: _projectId),
        manuscript: manuscript,
        sync: sync,
        ai: ai,
      ),
    );
    await settle(tester);
  }

  AppLocalizations stringsOf(WidgetTester tester) =>
      AppLocalizations.of(tester.element(find.byType(WritingScreen)));

  testWidgets('the plan shows the scenes of the repository', (tester) async {
    useSurface(tester, const Size(1440, 1100));
    await pumpScreen(tester);

    final Finder plan = find.byType(WritingOutlinePanel);
    expect(
      find.descendant(of: plan, matching: find.text('La plage à marée basse')),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: plan,
        matching: find.text('Ce que le comptoir bavarde'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: plan,
        matching: find.text('La cloche de Saint-Mérien'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('the manuscript shows the document of the opened scene', (
    tester,
  ) async {
    useSurface(tester, const Size(1440, 1100));
    await pumpScreen(tester);

    expect(find.byType(LimpidSceneEditor), findsOneWidget);
    expect(find.text('La plage à marée basse'), findsWidgets);
    // Le **texte** du manuscrit est rendu par l'editeur : il ne suffit
    // pas que le CRDT le porte, l'auteur doit le voir.
    expect(
      find.byWidgetPredicate((Widget widget) {
        if (widget is! RichText) return false;
        return widget.text.toPlainText().contains('Bonjour le monde');
      }),
      findsWidgets,
    );
  });

  testWidgets('the word counter follows the real content', (tester) async {
    useSurface(tester, const Size(1440, 1100));
    await pumpScreen(tester);

    final AppLocalizations strings = stringsOf(tester);
    expect(find.text(strings.writingWords(3)), findsOneWidget);
    expect(find.text(strings.writingWords(640)), findsNothing);
  });

  testWidgets('an edition hands its operations over to the repository', (
    tester,
  ) async {
    useSurface(tester, const Size(1440, 1100));
    await pumpScreen(tester);

    const UpdateContentOp operation = UpdateContentOp(
      doc: DocumentId(_firstDocumentId),
      lamport: 2,
      author: kFakeAuthor,
      blockId: BlockId('block-1'),
      content: TextContent('Bonjour le monde et la nuit'),
    );

    final LimpidSceneEditor editor = tester.widget<LimpidSceneEditor>(
      find.byType(LimpidSceneEditor),
    );
    editor.onChanged!(const <SyncOp>[operation]);
    await settle(tester);

    expect(manuscript.appliedOperations, hasLength(1));
    expect(manuscript.operations, contains(operation));

    final AppLocalizations strings = stringsOf(tester);
    expect(find.text(strings.writingWords(6)), findsOneWidget);
  });

  testWidgets('the offline banner appears when the device goes offline', (
    tester,
  ) async {
    useSurface(tester, const Size(1440, 1100));
    await pumpScreen(tester);

    final AppLocalizations strings = stringsOf(tester);
    expect(find.text(strings.editorOffline), findsNothing);

    sync.emit(SyncStatus.offline);
    await settle(tester);

    expect(find.text(strings.editorOffline), findsOneWidget);
  });

  testWidgets('the assistant shows the fragments as they arrive', (
    tester,
  ) async {
    useSurface(tester, const Size(1440, 1100));
    ai.fragments.addAll(<String>['La cloche sonna', ' à quatre heures douze.']);
    await pumpScreen(tester);

    final AppLocalizations strings = stringsOf(tester);

    await tester.tap(
      find.descendant(
        of: find.byType(WritingToolbar),
        matching: find.text(strings.editorAiTitle),
      ),
    );
    await settle(tester);

    await tester.enterText(find.byType(TextField), 'Continue la scène');
    await tester.tap(find.widgetWithText(LimpidButton, strings.editorAiSend));
    await tester.pump(const Duration(milliseconds: 25));
    await tester.pump();

    expect(find.text('La cloche sonna'), findsOneWidget);
    expect(find.text('La cloche sonna à quatre heures douze.'), findsNothing);

    await tester.pump(const Duration(milliseconds: 25));
    await tester.pump();

    expect(find.text('La cloche sonna à quatre heures douze.'), findsOneWidget);
    expect(ai.requests, hasLength(1));
    expect(ai.requests.single.sceneId, _firstSceneId);
    expect(ai.requests.single.selection, 'Bonjour le monde');
  });

  testWidgets('picking a scene in the plan opens it', (tester) async {
    useSurface(tester, const Size(1440, 1100));
    await pumpScreen(tester);

    final AppLocalizations strings = stringsOf(tester);

    await tester.tap(
      find.descendant(
        of: find.byType(WritingOutlinePanel),
        matching: find.text('Ce que le comptoir bavarde'),
      ),
    );
    await settle(tester);

    expect(find.text('Ce que le comptoir bavarde'), findsWidgets);
    // Le compteur suit le contenu réel du document, pas le nombre de mots
    // que le dépôt porte sur la scène.
    expect(find.text(strings.writingWords(6)), findsOneWidget);
    expect(find.text(strings.writingWords(3)), findsNothing);
  });

  testWidgets('the reading mode makes the manuscript read only', (
    tester,
  ) async {
    useSurface(tester, const Size(1440, 1100));
    await pumpScreen(tester);

    final AppLocalizations strings = stringsOf(tester);

    expect(
      tester.widget<LimpidSceneEditor>(find.byType(LimpidSceneEditor)).readOnly,
      isFalse,
    );

    await tester.tap(
      find.descendant(
        of: find.byType(WritingToolbar),
        matching: find.text(strings.editorReadMode),
      ),
    );
    await settle(tester);

    expect(
      tester.widget<LimpidSceneEditor>(find.byType(LimpidSceneEditor)).readOnly,
      isTrue,
    );
  });

  testWidgets('the plan creates a scene in a chapter', (tester) async {
    useSurface(tester, const Size(1440, 1100));
    await pumpScreen(tester);

    final AppLocalizations strings = stringsOf(tester);

    await tester.tap(
      find
          .descendant(
            of: find.byType(WritingOutlinePanel),
            matching: find.byTooltip(strings.hierarchyAddScene),
          )
          .first,
    );
    await settle(tester);

    await tester.enterText(find.byType(TextField), 'La marée basse');
    await settle(tester);
    await tester.tap(find.widgetWithText(LimpidButton, strings.actionCreate));
    await settle(tester);

    final List<Scene> scenes = manuscript.scenes['chapitre-1']!;
    expect(scenes, hasLength(3));
    expect(scenes.last.title, 'La marée basse');
    expect(
      find.descendant(
        of: find.byType(WritingOutlinePanel),
        matching: find.text('La marée basse'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('the plan reorders the scenes of a chapter', (tester) async {
    useSurface(tester, const Size(1440, 1100));
    await pumpScreen(tester);

    final AppLocalizations strings = stringsOf(tester);
    final Finder plan = find.byType(WritingOutlinePanel);

    double topOf(String title) => tester
        .getTopLeft(find.descendant(of: plan, matching: find.text(title)))
        .dy;

    expect(
      topOf('La plage à marée basse'),
      lessThan(topOf('Ce que le comptoir bavarde')),
    );

    await tester.tap(
      find
          .descendant(
            of: plan,
            matching: find.byWidgetPredicate(
              (Widget widget) =>
                  widget is IconButton &&
                  widget.tooltip == strings.hierarchyMoveUp &&
                  widget.onPressed != null,
            ),
          )
          .last,
    );
    await settle(tester);

    expect(
      topOf('Ce que le comptoir bavarde'),
      lessThan(topOf('La plage à marée basse')),
    );
    expect(
      manuscript.scenes['chapitre-1']!.map((Scene scene) => scene.title),
      <String>['Ce que le comptoir bavarde', 'La plage à marée basse'],
    );
  });

  testWidgets('the plan shows a series that has no scene yet', (tester) async {
    // Une serie qui ne porte encore aucune scene n'est pas un plan vide :
    // l'auteur doit pouvoir lui ajouter un tome.
    useSurface(tester, const Size(1440, 1100));
    final FakeManuscriptRepository repository = FakeManuscriptRepository(
      series: <Series>[
        Series(
          id: const SeriesId('serie-1'),
          projectId: const ProjectId(_projectId),
          title: 'La Saga du sel',
          order: OrderKey('1'),
        ),
      ],
    );

    await tester.pumpWidget(
      harness(
        const WritingScreen(projectId: _projectId),
        manuscript: repository,
        sync: sync,
        ai: ai,
      ),
    );
    await settle(tester);

    final Finder plan = find.byType(WritingOutlinePanel);
    expect(
      find.descendant(of: plan, matching: find.text('La Saga du sel')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('outline-add-volume-serie-1')),
      findsOneWidget,
    );
  });
}
