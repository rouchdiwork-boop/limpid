import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:limpid_app/l10n/generated/app_localizations.dart';
import 'package:limpid_app/src/domain/providers.dart';
import 'package:limpid_app/src/domain/revision_repository.dart';
import 'package:limpid_app/src/features/revision/revision_panel.dart';
import 'package:limpid_app/src/features/revision/revision_providers.dart';
import 'package:limpid_app/src/features/writing/widgets/writing_toolbar.dart';
import 'package:limpid_app/src/features/writing/writing_screen.dart';
import 'package:limpid_core/limpid_core.dart';
import 'package:limpid_design_system/limpid_design_system.dart';
import 'package:limpid_quill/limpid_quill.dart';

import '../../editor/fakes.dart';
import 'fakes.dart';

/// The identifier of the scene opened first.
const String _kSceneId = 'scene-1';

/// The identifier of the document of the scene.
const String _kDocumentId = 'scene-1-document';

/// The text of the scene.
const String _kSceneText = 'Le sel qui vient des murs recouvre les vitres.';

/// The body of the comment of the test.
const String _kCommentBody = 'Ce sel est deja pose au chapitre I';

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

/// Builds the document of the scene: a paragraph carrying a comment mark.
CrdtDocument buildDocument() {
  final DocumentId id = const DocumentId(_kDocumentId);
  return CrdtDocument.empty(id)
      .apply(
        InsertBlockOp(
          doc: id,
          lamport: 1,
          author: kFakeAuthor,
          blockId: const BlockId('block-1'),
          parent: null,
          order: OrderKey.initial,
          type: BlockType.paragraph,
          content: const TextContent(_kSceneText),
        ),
      )
      .apply(
        AddMarkOp(
          doc: id,
          lamport: 2,
          author: kFakeAuthor,
          markId: const MarkId('marque-1'),
          blockId: const BlockId('block-1'),
          type: MarkType.comment,
          range: const MarkRange(start: 0, end: 10),
          body: _kCommentBody,
        ),
      );
}

/// Builds the repository of the manuscript.
FakeManuscriptRepository buildManuscriptRepository() {
  return FakeManuscriptRepository(
    chapters: <Chapter>[
      const Chapter(
        id: ChapterId('chapitre-1'),
        title: 'Le sel',
        order: OrderKey.initial,
      ),
    ],
    scenes: <String, List<Scene>>{
      'chapitre-1': <Scene>[
        const Scene(
          id: SceneId(_kSceneId),
          chapterId: ChapterId('chapitre-1'),
          documentId: DocumentId(_kDocumentId),
          title: 'La plage a maree basse',
          order: OrderKey.initial,
        ),
      ],
    },
    documents: <String, CrdtDocument>{_kDocumentId: buildDocument()},
  );
}

/// Builds the repository of the review.
FakeRevisionRepository buildRevisionRepository() {
  return FakeRevisionRepository(
    threads: <CommentThread>[
      fakeThread(
        id: 'fil-1',
        markId: 'marque-1',
        comments: <Comment>[
          fakeComment(
            id: 'message-1',
            threadId: 'fil-1',
            authorId: 'auteur-2',
            body: _kCommentBody,
          ),
        ],
      ),
    ],
    members: <ProjectMember>[
      fakeMember(
        id: 'auteur-1',
        displayName: 'Ines Barreau',
        role: ProjectRole.owner,
      ),
      fakeMember(
        id: 'auteur-2',
        displayName: 'Thomas Derval',
        role: ProjectRole.betaReader,
      ),
    ],
  );
}

/// Wraps the screen in a provider scope holding the fakes.
Widget harness({
  required FakeManuscriptRepository manuscript,
  required FakeRevisionRepository revision,
}) {
  return ProviderScope(
    overrides: [
      manuscriptRepositoryProvider.overrideWithValue(manuscript),
      syncRepositoryProvider.overrideWithValue(FakeSyncRepository()),
      aiRepositoryProvider.overrideWithValue(FakeAiRepository()),
      revisionRepositoryProvider.overrideWithValue(revision),
      authorIdProvider.overrideWithValue(kRevisionAuthor),
    ],
    child: MaterialApp(
      theme: LimpidTheme.of(LimpidThemeVariant.paper),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: const WritingScreen(projectId: kRevisionProjectId),
    ),
  );
}

void main() {
  late FakeManuscriptRepository manuscript;
  late FakeRevisionRepository revision;

  setUp(() {
    manuscript = buildManuscriptRepository();
    revision = buildRevisionRepository();
  });

  Future<void> pumpScreen(WidgetTester tester) async {
    await tester.pumpWidget(
      harness(manuscript: manuscript, revision: revision),
    );
    await settle(tester);
  }

  AppLocalizations stringsOf(WidgetTester tester) =>
      AppLocalizations.of(tester.element(find.byType(WritingScreen)));

  /// Opens the panel of the review.
  Future<void> openReview(WidgetTester tester) async {
    final AppLocalizations strings = stringsOf(tester);
    await tester.tap(
      find.descendant(
        of: find.byType(WritingToolbar),
        matching: find.text(strings.writingReview),
      ),
    );
    await settle(tester);
  }

  testWidgets('the review panel opens next to the manuscript', (tester) async {
    useSurface(tester, const Size(1440, 1100));
    await pumpScreen(tester);

    expect(find.byType(RevisionPanel), findsNothing);

    await openReview(tester);

    expect(find.byType(RevisionPanel), findsOneWidget);
    expect(find.text(_kCommentBody), findsOneWidget);
  });

  testWidgets('the review panel lies under the manuscript on a narrow screen', (
    tester,
  ) async {
    useSurface(tester, const Size(900, 1100));
    await pumpScreen(tester);

    await openReview(tester);

    expect(find.byType(RevisionPanel), findsOneWidget);
    final double panelTop = tester.getTopLeft(find.byType(RevisionPanel)).dy;
    final double manuscriptTop = tester
        .getTopLeft(find.byType(LimpidSceneEditor))
        .dy;
    expect(panelTop, greaterThan(manuscriptTop));
  });

  testWidgets('clicking a comment puts its passage in relief', (tester) async {
    useSurface(tester, const Size(1440, 1100));
    await pumpScreen(tester);
    await openReview(tester);

    final LimpidSceneEditor editor = tester.widget<LimpidSceneEditor>(
      find.byType(LimpidSceneEditor),
    );
    expect(editor.commentAnchors, hasLength(1));
    expect(editor.commentAnchors.single.id, 'marque-1');
    expect(
      editor.commentAnchors.single.range,
      const MarkRange(start: 0, end: 10),
    );

    await tester.tap(find.text(_kCommentBody));
    await settle(tester);

    expect(find.text('Le sel qui'), findsOneWidget);

    final ProviderContainer container = ProviderScope.containerOf(
      tester.element(find.byType(RevisionPanel)),
    );
    expect(
      container.read(revisionSelectionProvider(kRevisionProjectId)).anchorId,
      'marque-1',
    );
  });

  testWidgets('closing a thread removes it from the open list', (tester) async {
    useSurface(tester, const Size(1440, 1100));
    await pumpScreen(tester);
    await openReview(tester);

    final AppLocalizations strings = stringsOf(tester);
    await tester.tap(
      find.widgetWithText(LimpidButton, strings.revisionResolve),
    );
    await settle(tester);

    expect(revision.saved, hasLength(1));
    expect(revision.saved.single.isResolved, isTrue);
    expect(find.text(_kCommentBody), findsNothing);
  });
}
