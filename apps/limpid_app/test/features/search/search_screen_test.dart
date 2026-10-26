import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:limpid_app/l10n/generated/app_localizations.dart';
import 'package:limpid_app/src/domain/providers.dart';
import 'package:limpid_app/src/domain/search_repository.dart';
import 'package:limpid_app/src/editor/editor_controller.dart';
import 'package:limpid_app/src/editor/editor_models.dart';
import 'package:limpid_app/src/features/search/search_providers.dart';
import 'package:limpid_app/src/features/search/search_result_tile.dart';
import 'package:limpid_app/src/features/search/search_screen.dart';
import 'package:limpid_core/limpid_core.dart';
import 'package:limpid_design_system/limpid_design_system.dart';

import '../../editor/fakes.dart';

/// The identifier of the project of the tests.
const String _projectId = 'project-1';

/// The scene that carries the passage of the tests.
const String _foundSceneId = 'scene-2';

/// A search repository that answers with the passages it was given.
final class FakeSearchRepository implements SearchRepository {
  /// Creates the fake.
  FakeSearchRepository({this.results = const <SearchResult>[]});

  /// The passages the fake answers with.
  final List<SearchResult> results;

  /// The queries the screen asked.
  final List<String> queries = <String>[];

  @override
  Future<List<SearchResult>> search(
    String query, {
    int limit = defaultSearchLimit,
  }) async {
    queries.add(query);
    return results;
  }
}

/// The writing screen of the tests: it records the project it was opened on.
class WritingStub extends StatelessWidget {
  /// Creates the stub.
  const WritingStub({required this.projectId, super.key});

  /// The project the screen was opened on.
  final String projectId;

  @override
  Widget build(BuildContext context) => Text('écriture: $projectId');
}

/// The manuscripts of the tests: one chapter, two scenes.
FakeManuscriptRepository buildManuscripts() => FakeManuscriptRepository(
  chapters: <Chapter>[
    Chapter(
      id: const ChapterId('chapter-1'),
      title: 'Le sel',
      order: OrderKey('1'),
    ),
  ],
  scenes: <String, List<Scene>>{
    'chapter-1': <Scene>[
      Scene(
        id: const SceneId('scene-1'),
        chapterId: const ChapterId('chapter-1'),
        documentId: const DocumentId('document-1'),
        title: 'La plage à marée basse',
        order: OrderKey('1'),
      ),
      Scene(
        id: const SceneId(_foundSceneId),
        chapterId: const ChapterId('chapter-1'),
        documentId: const DocumentId('document-2'),
        title: 'Ce que le comptoir bavarde',
        order: OrderKey('2'),
      ),
    ],
  },
);

/// The passage the fake search answers with.
SearchResult buildResult() => const SearchResult(
  blockId: 'block-1',
  sceneId: _foundSceneId,
  sceneTitle: 'Ce que le comptoir bavarde',
  projectId: _projectId,
  projectTitle: 'Les Heures de Cendre',
  documentId: 'document-2',
  excerpt: 'Le comptoir bavarde toute la journée.',
  highlights: <SearchHighlight>[SearchHighlight(start: 4, end: 12)],
  relevance: 1,
);

void main() {
  late FakeSearchRepository search;

  setUp(() {
    search = FakeSearchRepository(results: <SearchResult>[buildResult()]);
  });

  Widget harness({FakeManuscriptRepository? manuscripts}) {
    final GoRouter router = GoRouter(
      routes: <RouteBase>[
        GoRoute(path: '/', builder: (context, state) => const SearchScreen()),
        GoRoute(
          path: '/projets/:projectId/ecriture',
          builder: (context, state) =>
              WritingStub(projectId: state.pathParameters['projectId'] ?? ''),
        ),
      ],
    );
    addTearDown(router.dispose);
    return ProviderScope(
      overrides: [
        searchRepositoryProvider.overrideWithValue(search),
        manuscriptRepositoryProvider.overrideWithValue(
          manuscripts ?? buildManuscripts(),
        ),
      ],
      child: MaterialApp.router(
        routerConfig: router,
        theme: LimpidTheme.of(LimpidThemeVariant.paper),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        // Les textes de l'ecran sont asserts en francais : la locale est
        // posee, sinon le poste de test choisirait l'anglais.
        locale: const Locale('fr'),
      ),
    );
  }

  /// The strings of the screen, read from the tree the test just built.
  AppLocalizations stringsOf(WidgetTester tester) {
    return AppLocalizations.of(tester.element(find.byType(SearchScreen)));
  }

  /// Types [query] in the field of the screen and waits for the search.
  Future<void> searchFor(WidgetTester tester, String query) async {
    await tester.enterText(find.byType(TextField), query);
    await tester.pump(const Duration(milliseconds: 250));
    await tester.pumpAndSettle();
  }

  testWidgets('the screen lists the passages the search found', (tester) async {
    await tester.pumpWidget(harness());
    await tester.pumpAndSettle();

    await searchFor(tester, 'bavarde');

    expect(find.byType(SearchResultTile), findsOneWidget);
    expect(find.text('Ce que le comptoir bavarde'), findsWidgets);
    expect(find.text('Les Heures de Cendre'), findsOneWidget);
    expect(search.queries, contains('bavarde'));
  });

  testWidgets('the screen waits for a query before it searches', (
    tester,
  ) async {
    await tester.pumpWidget(harness());
    await tester.pumpAndSettle();

    expect(find.text(stringsOf(tester).searchIdleTitle), findsOneWidget);
    expect(search.queries, isEmpty);
  });

  testWidgets('the screen says when no passage carries the query', (
    tester,
  ) async {
    search = FakeSearchRepository();
    await tester.pumpWidget(harness());
    await tester.pumpAndSettle();

    await searchFor(tester, 'hippopotame');

    expect(find.byType(SearchResultTile), findsNothing);
    expect(find.text(stringsOf(tester).searchEmptyTitle), findsOneWidget);
  });

  testWidgets('picking a passage opens the scene that carries it', (
    tester,
  ) async {
    await tester.pumpWidget(harness());
    await tester.pumpAndSettle();

    await searchFor(tester, 'bavarde');
    await tester.tap(find.byType(SearchResultTile));
    await tester.pumpAndSettle();

    expect(find.byType(WritingStub), findsOneWidget);
    expect(find.text('écriture: $_projectId'), findsOneWidget);

    final ProviderContainer container = ProviderScope.containerOf(
      tester.element(find.byType(WritingStub)),
    );
    addTearDown(container.dispose);
    final WritingState state = container.read(
      writingControllerProvider(_projectId),
    );
    expect(state.activeScene?.id.value, _foundSceneId);
  });
}
