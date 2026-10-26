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
import 'package:limpid_app/src/features/writing/widgets/writing_outline_panel.dart';
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

/// The title of the series the author creates during the journey.
const String kSeriesTitle = 'Les Saisons';

/// The title of the tome the author creates during the journey.
const String kVolumeTitle = 'L\'Automne';

/// The title of the chapter the author creates during the journey.
const String kChapterTitle = 'La falaise';

/// The title of the scene the author creates during the journey.
const String kSceneTitle = 'La marée basse';

/// The words the author adds to the paragraph.
const String kContinuation = ' Le vent se levait.';

/// The paragraph once the author has written.
const String kParagraph = 'Il pleuvait sur la falaise.$kContinuation';

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

      // 6. The studio opens on the plan of the book.
      await tester.tap(
        find.widgetWithText(LimpidButton, strings.projectContinueWriting),
      );
      await tester.pumpAndSettle();
      expect(find.byType(WritingScreen), findsOneWidget);
      expect(find.byType(WritingOutlinePanel), findsOneWidget);

      // 7. The author builds the hierarchy of the book **from the plan**:
      // the series, the tome, the chapter and the scene. Nothing is written
      // in the database by the test: every level is created by the interface.
      await _createFromThePlan(
        tester,
        strings,
        'outline-add-series',
        kSeriesTitle,
      );
      await _createFromThePlan(
        tester,
        strings,
        'outline-add-volume-',
        kVolumeTitle,
      );
      await _createFromThePlan(
        tester,
        strings,
        'outline-add-chapter-',
        kChapterTitle,
      );
      await _createFromThePlan(
        tester,
        strings,
        'outline-add-scene-',
        kSceneTitle,
      );

      final Finder plan = find.byType(WritingOutlinePanel);
      expect(
        find.descendant(of: plan, matching: find.text(kSeriesTitle)),
        findsOneWidget,
      );
      expect(
        find.descendant(of: plan, matching: find.text(kVolumeTitle)),
        findsOneWidget,
      );
      expect(
        find.descendant(of: plan, matching: find.text(kChapterTitle)),
        findsOneWidget,
      );
      expect(
        find.descendant(of: plan, matching: find.text(kSceneTitle)),
        findsOneWidget,
      );

      // 8. The author writes in the scene the interface created.
      final QuillController editor = tester
          .widget<QuillEditor>(find.byType(QuillEditor))
          .controller;

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

      // 9. The manuscript survives the restart: the text is persisted, not
      // only displayed.
      final List<Scene> scenes = await manuscripts.listScenes(
        (await manuscripts.listChaptersOfVolume(
          (await manuscripts.listVolumes(
            (await manuscripts.listSeries(
              projects.single.id.value,
            )).single.id.value,
          )).single.id.value,
        )).single.id.value,
      );
      expect(scenes, hasLength(1));

      final CrdtDocument document = await manuscripts.loadDocument(
        scenes.single.documentId.value,
      );
      expect(document.blocks, hasLength(1));
      expect(document.blocks.single.content.plainText, kParagraph);

      // 10. The hierarchy survives the restart too : a **new** repository,
      // opened on the same database, finds the book the interface built.
      final LocalManuscriptRepository afterRestart = LocalManuscriptRepository(
        database: database,
        author: kAuthor,
      );
      final List<Series> series = await afterRestart.listSeries(
        projects.single.id.value,
      );
      expect(series, hasLength(1));
      expect(series.single.title, kSeriesTitle);

      final List<Volume> volumes = await afterRestart.listVolumes(
        series.single.id.value,
      );
      expect(volumes, hasLength(1));
      expect(volumes.single.title, kVolumeTitle);

      final List<Chapter> chapters = await afterRestart.listChaptersOfVolume(
        volumes.single.id.value,
      );
      expect(chapters, hasLength(1));
      expect(chapters.single.title, kChapterTitle);

      final List<Scene> persisted = await afterRestart.listScenes(
        chapters.single.id.value,
      );
      expect(persisted, hasLength(1));
      expect(persisted.single.title, kSceneTitle);
    });
  });
}

/// Creates an element of the hierarchy from the plan of the book.
///
/// The test drives the interface : elle presse le bouton du niveau, elle
/// écrit le titre dans la boîte de dialogue, elle valide. La base n'est
/// jamais touchée directement.
Future<void> _createFromThePlan(
  WidgetTester tester,
  AppLocalizations strings,
  String prefix,
  String title,
) async {
  await tester.tap(_action(prefix));
  await tester.pumpAndSettle();

  await tester.enterText(find.byType(TextField), title);
  await tester.pumpAndSettle();
  await tester.tap(find.widgetWithText(LimpidButton, strings.actionCreate));
  await tester.pumpAndSettle();
}

/// The action of the plan whose key starts with [prefix].
///
/// Les actions du plan portent une cle : le test les trouve sans dependre
/// du libelle annonce, qui change avec la langue.
///
/// Le plan porte deux familles d'actions : celles d'une ligne — un bouton
/// d'icone, dans la ligne du tome ou du chapitre — et celle du projet
/// entier, un bouton large qui porte son libelle. Les deux familles
/// partagent le prefixe du chapitre : le test cherche donc toujours le
/// bouton d'icone, jamais celui du projet.
Finder _action(String prefix) => find.descendant(
  of: find.byWidgetPredicate((Widget widget) {
    final Key? key = widget.key;
    return key is ValueKey<String> && key.value.startsWith(prefix);
  }),
  matching: find.byType(IconButton),
);

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
