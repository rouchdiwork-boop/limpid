import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:limpid_app/l10n/generated/app_localizations.dart';
import 'package:limpid_app/src/domain/providers.dart';
import 'package:limpid_app/src/features/dashboard/dashboard_screen.dart';
import 'package:limpid_app/src/features/projects/projects_providers.dart';
import 'package:limpid_core/limpid_core.dart';
import 'package:limpid_design_system/limpid_design_system.dart';

import '../projects/fakes.dart';

void main() {
  /// The day the tests read.
  final DateTime today = DateTime.utc(2026, 10, 25);

  /// Gives the test a viewport large enough for the desktop layout.
  void useSurface(WidgetTester tester, Size size) {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  /// The manuscripts the dashboard reads.
  FakeManuscriptRepository library() {
    return FakeManuscriptRepository(
      projects: <Project>[
        fakeProject(
          id: 'heures',
          title: 'Les Heures de Cendre',
          status: ManuscriptStatus.writing,
          chapterIds: <String>['c1'],
        ),
      ],
      chapters: <String, List<Chapter>>{
        'heures': <Chapter>[
          fakeChapter(
            id: 'c1',
            targetWordCount: 6000,
            sceneIds: <String>['s0', 's1', 's2', 's3'],
          ),
        ],
      },
      scenes: <String, List<Scene>>{
        'c1': <Scene>[
          fakeScene(
            id: 's0',
            chapterId: 'c1',
            wordCount: 4000,
            updatedAt: today.subtract(const Duration(days: 20)),
          ),
          fakeScene(
            id: 's1',
            chapterId: 'c1',
            wordCount: 100,
            updatedAt: today,
          ),
          fakeScene(
            id: 's2',
            chapterId: 'c1',
            wordCount: 250,
            updatedAt: today.subtract(const Duration(days: 1)),
          ),
          fakeScene(id: 's3', chapterId: 'c1', wordCount: 0),
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
        todayProvider.overrideWithValue(today),
      ],
      child: MaterialApp(
        theme: LimpidTheme.of(LimpidThemeVariant.paper),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(body: child),
      ),
    );
  }

  testWidgets('the dashboard shows the figures of the repository', (
    tester,
  ) async {
    useSurface(tester, const Size(1440, 1100));
    await tester.pumpWidget(
      harness(
        child: const DashboardScreen(),
        manuscripts: library(),
        preferences: FakePreferencesRepository(goal: 1500, streak: 7),
      ),
    );
    await tester.pumpAndSettle();

    final AppLocalizations strings = AppLocalizations.of(
      tester.element(find.byType(DashboardScreen)),
    );

    expect(find.text(strings.dashboardTitle), findsOneWidget);
    expect(find.text(strings.dashboardTodayWords), findsOneWidget);
    expect(find.text('100'), findsOneWidget);
    expect(find.text('350'), findsOneWidget);
    expect(find.text('4 350'), findsOneWidget);
    expect(find.text('7'), findsOneWidget);
    expect(find.text(strings.dashboardGoalOf('1 500', '7')), findsOneWidget);
    expect(find.text('Les Heures de Cendre'), findsWidgets);
  });

  testWidgets('the dashboard shows the streak of the preferences', (
    tester,
  ) async {
    useSurface(tester, const Size(1440, 1100));
    await tester.pumpWidget(
      harness(
        child: const DashboardScreen(),
        manuscripts: library(),
        preferences: FakePreferencesRepository(goal: 1500, streak: 12),
      ),
    );
    await tester.pumpAndSettle();

    final AppLocalizations strings = AppLocalizations.of(
      tester.element(find.byType(DashboardScreen)),
    );

    expect(find.text(strings.dashboardStreak), findsOneWidget);
    expect(find.text('12'), findsOneWidget);
  });

  testWidgets('the dashboard shows the failure state when the library fails', (
    tester,
  ) async {
    useSurface(tester, const Size(1440, 1100));
    final FakeManuscriptRepository manuscripts = FakeManuscriptRepository()
      ..error = StateError('the database is closed');

    await tester.pumpWidget(
      harness(child: const DashboardScreen(), manuscripts: manuscripts),
    );
    await tester.pumpAndSettle();

    final AppLocalizations strings = AppLocalizations.of(
      tester.element(find.byType(DashboardScreen)),
    );

    expect(find.text(strings.errorGeneric), findsOneWidget);
    expect(find.text(strings.actionRetry), findsOneWidget);
  });

  testWidgets('the dashboard shows the empty state without manuscript', (
    tester,
  ) async {
    useSurface(tester, const Size(1440, 1100));
    await tester.pumpWidget(
      harness(
        child: const DashboardScreen(),
        manuscripts: FakeManuscriptRepository(),
      ),
    );
    await tester.pumpAndSettle();

    final AppLocalizations strings = AppLocalizations.of(
      tester.element(find.byType(DashboardScreen)),
    );

    expect(find.text(strings.dataEmptyTitle), findsOneWidget);
    expect(find.text(strings.dataEmptyMessage), findsOneWidget);
  });
}
