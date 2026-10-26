import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:limpid_app/l10n/generated/app_localizations.dart';
import 'package:limpid_app/src/domain/providers.dart';
import 'package:limpid_app/src/features/library/library_screen.dart';
import 'package:limpid_app/src/features/projects/projects_providers.dart';
import 'package:limpid_core/limpid_core.dart';
import 'package:limpid_design_system/limpid_design_system.dart';

import '../projects/fakes.dart';

void main() {
  /// Gives the test a viewport large enough for the desktop layout.
  void useSurface(WidgetTester tester, Size size) {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  /// The manuscripts the library reads.
  FakeManuscriptRepository library() {
    return FakeManuscriptRepository(
      projects: <Project>[
        fakeProject(
          id: 'heures',
          title: 'Les Heures de Cendre',
          status: ManuscriptStatus.writing,
          chapterIds: <String>['c1'],
        ),
        fakeProject(
          id: 'dune',
          title: 'Carnets de dune',
          status: ManuscriptStatus.draft,
        ),
        fakeProject(
          id: 'sieste',
          title: 'Les Machines de sieste',
          status: ManuscriptStatus.published,
        ),
      ],
      chapters: <String, List<Chapter>>{
        'heures': <Chapter>[
          fakeChapter(
            id: 'c1',
            targetWordCount: 6000,
            sceneIds: <String>['s1'],
          ),
        ],
      },
      scenes: <String, List<Scene>>{
        'c1': <Scene>[
          fakeScene(
            id: 's1',
            chapterId: 'c1',
            wordCount: 120,
            updatedAt: DateTime.utc(2026, 10, 25),
          ),
        ],
      },
    );
  }

  Widget harness({
    required Widget child,
    FakeManuscriptRepository? manuscripts,
    FakePreferencesRepository? preferences,
  }) {
    return ProviderScope(
      overrides: [
        manuscriptRepositoryProvider.overrideWithValue(
          manuscripts ?? FakeManuscriptRepository(),
        ),
        preferencesRepositoryProvider.overrideWithValue(
          preferences ?? FakePreferencesRepository(),
        ),
        todayProvider.overrideWithValue(DateTime.utc(2026, 10, 25)),
      ],
      child: MaterialApp(
        theme: LimpidTheme.of(LimpidThemeVariant.paper),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(body: child),
      ),
    );
  }

  testWidgets('the library lists every manuscript of the author', (
    tester,
  ) async {
    useSurface(tester, const Size(1440, 1100));
    await tester.pumpWidget(
      harness(child: const LibraryScreen(), manuscripts: library()),
    );
    await tester.pumpAndSettle();

    final AppLocalizations strings = AppLocalizations.of(
      tester.element(find.byType(LibraryScreen)),
    );

    expect(find.text(strings.libraryTitle), findsOneWidget);
    expect(find.text(strings.librarySubtitle(3, 1)), findsOneWidget);
    expect(find.text('Les Heures de Cendre'), findsWidgets);
    expect(find.text('Carnets de dune'), findsWidgets);
    expect(find.text('Les Machines de sieste'), findsWidgets);
  });

  testWidgets('the library filters the manuscripts by status', (tester) async {
    useSurface(tester, const Size(1440, 1100));
    await tester.pumpWidget(
      harness(child: const LibraryScreen(), manuscripts: library()),
    );
    await tester.pumpAndSettle();

    final AppLocalizations strings = AppLocalizations.of(
      tester.element(find.byType(LibraryScreen)),
    );

    await tester.tap(
      find.widgetWithText(LimpidChip, strings.libraryFilterPublished),
    );
    await tester.pumpAndSettle();

    expect(find.text('Carnets de dune'), findsNothing);
    expect(find.text('Les Machines de sieste'), findsWidgets);
  });

  testWidgets('the library shows the empty state without manuscript', (
    tester,
  ) async {
    useSurface(tester, const Size(1440, 1100));
    await tester.pumpWidget(
      harness(
        child: const LibraryScreen(),
        manuscripts: FakeManuscriptRepository(),
      ),
    );
    await tester.pumpAndSettle();

    final AppLocalizations strings = AppLocalizations.of(
      tester.element(find.byType(LibraryScreen)),
    );

    expect(find.text(strings.dataEmptyTitle), findsOneWidget);
    expect(find.text(strings.dataEmptyMessage), findsOneWidget);
  });

  testWidgets('the library shows the failure state when the repository fails', (
    tester,
  ) async {
    useSurface(tester, const Size(1440, 1100));
    final FakeManuscriptRepository manuscripts = FakeManuscriptRepository()
      ..error = StateError('the database is closed');

    await tester.pumpWidget(
      harness(child: const LibraryScreen(), manuscripts: manuscripts),
    );
    await tester.pumpAndSettle();

    final AppLocalizations strings = AppLocalizations.of(
      tester.element(find.byType(LibraryScreen)),
    );

    expect(find.text(strings.errorGeneric), findsOneWidget);
    expect(find.text(strings.actionRetry), findsOneWidget);
  });

  testWidgets('the library shows the word count of the scenes', (tester) async {
    useSurface(tester, const Size(1440, 1100));
    await tester.pumpWidget(
      harness(child: const LibraryScreen(), manuscripts: library()),
    );
    await tester.pumpAndSettle();

    final AppLocalizations strings = AppLocalizations.of(
      tester.element(find.byType(LibraryScreen)),
    );

    // The tile shows the word count and the completion on the same line.
    expect(find.textContaining(strings.libraryWords('120')), findsOneWidget);
  });
}
