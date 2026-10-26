// The end-to-end journey of an author.
//
// The application runs on its real router, its real repositories and its real
// local database — held in memory — from the sign-in screen to the studio of
// writing. The session is the only thing simulated: the demonstration mode
// opens it locally, without a backend.
//
// `flutter_quill` is a transitive dependency of the application: the test
// needs the controller of the editor to drive it, and the application cannot
// declare the package without touching its `pubspec.yaml`.
// ignore_for_file: depend_on_referenced_packages

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart' hide Block;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:limpid_app/l10n/generated/app_localizations.dart';
import 'package:limpid_app/src/app/router.dart';
import 'package:limpid_app/src/auth/auth_repository.dart';
import 'package:limpid_app/src/auth/local_auth_store.dart';
import 'package:limpid_app/src/auth/session_controller.dart';
import 'package:limpid_app/src/auth/supabase_auth_repository.dart';
import 'package:limpid_app/src/data/app_database.dart';
import 'package:limpid_app/src/data/local_manuscript_repository.dart';
import 'package:limpid_app/src/data/local_preferences_repository.dart';
import 'package:limpid_app/src/data/local_sync_repository.dart';
import 'package:limpid_app/src/data/project_identity_store.dart';
import 'package:limpid_app/src/data/project_ops_transport.dart';
import 'package:limpid_app/src/domain/providers.dart';
import 'package:limpid_app/src/features/dashboard/dashboard_screen.dart';
import 'package:limpid_app/src/features/library/library_screen.dart';
import 'package:limpid_app/src/features/project/project_screen.dart';
import 'package:limpid_app/src/features/writing/writing_screen.dart';
import 'package:limpid_core/limpid_core.dart';
import 'package:limpid_design_system/limpid_design_system.dart';

/// The author who writes the manuscript during the journey.
const AuthorId kAuthor = AuthorId('auteur-du-voyage');

/// The name of the author, as the sign-up form receives it.
const String kAuthorName = 'Camille Rivière';

/// The address of the author, as the sign-up form receives it.
const String kAuthorEmail = 'camille@example.test';

/// The title of the book the author creates during the journey.
const String kBookTitle = 'Les Heures de Cendre';

/// The identifier of the chapter of the project.
const String kChapterId = 'chapitre-1';

/// The title of the chapter of the project.
const String kChapterTitle = 'La falaise';

/// The identifier of the scene the author writes in.
const String kSceneId = 'scene-1';

/// The title of the scene the author writes in.
const String kSceneTitle = 'La marée basse';

/// The identifier of the CRDT document of the scene.
const String kDocumentId = 'document-scene-1';

/// The identifier of the block holding the paragraph of the scene.
const String kBlockId = 'block-1';

/// The paragraph the scene holds when the author opens it.
const String kFirstParagraph = 'Il pleuvait sur la falaise.';

/// The words the author adds to the paragraph.
const String kContinuation = ' Le vent se levait.';

/// The paragraph once the author has written.
const String kParagraph = '$kFirstParagraph$kContinuation';

/// The number of words of the paragraph.
const int kParagraphWords = 9;

/// The size of the viewport of the journey.
///
/// The window is wide enough for the desktop layout of the studio and narrow
/// enough for the shell to show its bottom bar: the theme selector of the
/// navigation rail overflows above 900 logical pixels, because the font of
/// the tests draws every glyph as a square.
const Size kViewport = Size(880, 1200);

/// The address of the API, unreachable: the journey never synchronises.
const String kUnreachableApi = 'http://127.0.0.1:9/';

void main() {
  group('the journey of an author', () {
    late AppDatabase database;
    late LocalManuscriptRepository manuscripts;
    late ProviderContainer container;

    setUp(() async {
      database = await AppDatabase.openWith(NativeDatabase.memory());
      addTearDown(database.close);

      manuscripts = LocalManuscriptRepository(
        database: database,
        author: kAuthor,
      );
      final http.Client client = http.Client();
      addTearDown(client.close);

      container = ProviderContainer(
        overrides: [
          authRepositoryProvider.overrideWithValue(
            DemoAuthRepository(store: InMemoryLocalAuthStore()),
          ),
          manuscriptRepositoryProvider.overrideWithValue(manuscripts),
          preferencesRepositoryProvider.overrideWithValue(
            LocalPreferencesRepository(database: database),
          ),
          syncRepositoryProvider.overrideWithValue(
            LocalSyncRepository(
              database: database,
              transport: ProjectOpsTransport(
                baseUrl: Uri.parse(kUnreachableApi),
                client: client,
                store: database.manuscripts,
                projects: ProjectIdentityStore(
                  database.sync,
                  authorId: kAuthor.value,
                ),
              ),
              author: kAuthor,
            ),
          ),
          authorIdProvider.overrideWithValue(kAuthor),
        ],
      );
      addTearDown(container.dispose);
    });

    testWidgets('the author signs up, creates a book and writes in it', (
      tester,
    ) async {
      tester.view.physicalSize = kViewport;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(buildApplication(container));
      await tester.pumpAndSettle();

      final AppLocalizations strings = stringsOf(tester);

      // 1. The application starts on the sign-in screen.
      expect(find.text(strings.signInTitle), findsOneWidget);
      expect(find.byType(DashboardScreen), findsNothing);

      // 2. The author signs up in demonstration mode: the session opens.
      await tester.tap(find.text(strings.signInCreateAccount));
      await tester.pumpAndSettle();
      expect(find.text(strings.signUpTitle), findsOneWidget);

      await tester.enterText(
        find.ancestor(
          of: find.text(strings.fieldAuthorName),
          matching: find.byType(TextField),
        ),
        kAuthorName,
      );
      await tester.enterText(
        find.ancestor(
          of: find.text(strings.fieldEmail),
          matching: find.byType(TextField),
        ),
        kAuthorEmail,
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.widgetWithText(LimpidButton, strings.actionSendLink),
      );
      await tester.pumpAndSettle();

      final AuthSession? session = container
          .read(sessionControllerProvider)
          .value;
      expect(session, isNotNull);
      expect(session?.email, kAuthorEmail);
      expect(session?.authorName, kAuthorName);
      expect(find.byType(DashboardScreen), findsOneWidget);

      // 3. The wizard of the startup creates the project.
      await tester.tap(
        find.widgetWithText(LimpidButton, strings.actionNewProject),
      );
      await tester.pumpAndSettle();
      expect(find.text(strings.onboardingStepOf(1, 4)), findsOneWidget);

      await tester.tap(
        find.widgetWithText(LimpidButton, strings.onboardingNext),
      );
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), kBookTitle);
      await tester.pumpAndSettle();
      await tester.tap(
        find.widgetWithText(LimpidButton, strings.onboardingNext),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.widgetWithText(LimpidButton, strings.onboardingNext),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.widgetWithText(LimpidButton, strings.onboardingCreateProject),
      );
      await tester.pumpAndSettle();

      final List<Project> projects = await manuscripts.listProjects();
      expect(projects, hasLength(1));
      expect(projects.single.title, kBookTitle);

      // The project holds a chapter, a scene and the paragraph the author
      // wrote the day before: the data layer is the real one.
      await manuscripts.saveChapter(
        const Chapter(
          id: ChapterId(kChapterId),
          title: kChapterTitle,
          order: OrderKey.initial,
        ),
      );
      await manuscripts.saveScene(
        const Scene(
          id: SceneId(kSceneId),
          chapterId: ChapterId(kChapterId),
          documentId: DocumentId(kDocumentId),
          title: kSceneTitle,
          order: OrderKey.initial,
        ),
      );
      await manuscripts.applyOperations(const <SyncOp>[
        InsertBlockOp(
          doc: DocumentId(kDocumentId),
          lamport: 1,
          author: kAuthor,
          blockId: BlockId(kBlockId),
          parent: null,
          order: OrderKey.initial,
          type: BlockType.paragraph,
          content: TextContent(kFirstParagraph),
        ),
      ]);

      // 4. The project appears in the library.
      //
      // The wizard invalidates the library itself: the test does not touch
      // the provider, so it proves that the application refreshes the
      // library on its own once the project is created.
      await tester.pumpAndSettle();

      await tester.tap(find.text(strings.navLibrary));
      await tester.pumpAndSettle();
      expect(find.byType(LibraryScreen), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(LibraryScreen),
          matching: find.text(kBookTitle),
        ),
        findsWidgets,
      );
      expect(
        find.descendant(
          of: find.byType(LibraryScreen),
          matching: find.text(strings.dataEmptyTitle),
        ),
        findsNothing,
      );

      // 5. The sheet of the project shows its chapters.
      await tester.tap(
        find
            .descendant(
              of: find.byType(LibraryScreen),
              matching: find.text(kBookTitle),
            )
            .first,
      );
      await tester.pumpAndSettle();
      expect(find.byType(ProjectScreen), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(ProjectScreen),
          matching: find.text(kChapterTitle),
        ),
        findsOneWidget,
      );

      // 6. The studio opens on the scene of the chapter.
      await tester.tap(
        find.widgetWithText(LimpidButton, strings.projectContinueWriting),
      );
      await tester.pumpAndSettle();
      expect(find.byType(WritingScreen), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(WritingScreen),
          matching: find.text(kSceneTitle),
        ),
        findsWidgets,
      );

      // The author leaves the studio and comes back: the editor is rebuilt
      // on the blocks of the CRDT document. It is the only moment the editor
      // knows the identifier of the block the scene holds — the editor is
      // built before the document arrives, and it never takes the blocks
      // that arrive later.
      container
          .read(appRouterProvider)
          .go(AppRoutes.project(projects.single.id.value));
      await tester.pumpAndSettle();
      expect(find.byType(ProjectScreen), findsOneWidget);

      await tester.tap(
        find.widgetWithText(LimpidButton, strings.projectContinueWriting),
      );
      await tester.pumpAndSettle();
      expect(find.byType(WritingScreen), findsOneWidget);

      final QuillController editor = tester
          .widget<QuillEditor>(find.byType(QuillEditor))
          .controller;

      // The author writes: the editor turns the text into CRDT operations
      // and hands them over to the controller, which writes them through the
      // repository.
      editor.replaceText(
        0,
        0,
        kParagraph,
        const TextSelection.collapsed(offset: kParagraph.length),
      );
      await tester.pumpAndSettle();

      expect(
        find.descendant(
          of: find.byType(WritingScreen),
          matching: find.text(strings.writingWords(kParagraphWords)),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byType(WritingScreen),
          matching: find.text(strings.editorSaved),
        ),
        findsOneWidget,
      );

      // The document is re-read from the local database: the text is
      // persisted, not only displayed.
      final CrdtDocument document = await manuscripts.loadDocument(kDocumentId);
      expect(document.blocks, hasLength(1));
      expect(document.blocks.single.content.plainText, kParagraph);
    });
  });
}

/// Builds the application under test.
///
/// The router, the repositories and the local database are the real ones:
/// only the session is simulated, in demonstration mode.
Widget buildApplication(ProviderContainer container) {
  return UncontrolledProviderScope(
    container: container,
    child: Consumer(
      builder: (BuildContext context, WidgetRef ref, Widget? child) =>
          MaterialApp.router(
            theme: LimpidTheme.of(LimpidThemeVariant.paper),
            routerConfig: ref.watch(appRouterProvider),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
          ),
    ),
  );
}

/// The localizations of the application, in the locale of the test.
AppLocalizations stringsOf(WidgetTester tester) =>
    AppLocalizations.of(tester.element(find.byType(Scaffold).first));
