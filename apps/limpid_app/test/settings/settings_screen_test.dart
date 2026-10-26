import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:limpid_app/l10n/generated/app_localizations.dart';
import 'package:limpid_app/src/app/router.dart';
import 'package:limpid_app/src/app/theme_controller.dart';
import 'package:limpid_app/src/auth/auth_repository.dart';
import 'package:limpid_app/src/auth/session_controller.dart';
import 'package:limpid_app/src/auth/supabase_auth_repository.dart';
import 'package:limpid_app/src/domain/providers.dart';
import 'package:limpid_app/src/domain/repositories.dart';
import 'package:limpid_app/src/features/settings/settings_screen.dart';
import 'package:limpid_core/limpid_core.dart';
import 'package:limpid_design_system/limpid_design_system.dart';

import '../onboarding/fakes.dart';

/// The application of the test: it follows the theme of the controller, as
/// the real application does.
class _ThemedApp extends ConsumerWidget {
  const _ThemedApp({required this.router});

  final GoRouter router;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final LimpidThemeVariant variant = ref.watch(themeControllerProvider);

    return MaterialApp.router(
      theme: LimpidTheme.of(variant),
      themeMode: variant.isDark ? ThemeMode.dark : ThemeMode.light,
      routerConfig: router,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
    );
  }
}

void main() {
  /// Gives the test a viewport large enough for the desktop layout.
  ///
  /// The page is tall: every row of the settings is visible, and the tests
  /// that tap one of them do not depend on the scroll position.
  void useSurface(WidgetTester tester) {
    tester.view.physicalSize = const Size(1440, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  /// Builds the application of the test, inside a router.
  Widget harness() {
    final GoRouter router = GoRouter(
      initialLocation: AppRoutes.settings,
      routes: <RouteBase>[
        GoRoute(
          path: AppRoutes.settings,
          builder: (BuildContext context, GoRouterState state) =>
              const SettingsScreen(),
        ),
        GoRoute(
          path: AppRoutes.signIn,
          builder: (BuildContext context, GoRouterState state) =>
              const Scaffold(body: Text('Connexion')),
        ),
      ],
    );
    addTearDown(router.dispose);

    return _ThemedApp(router: router);
  }

  AppLocalizations stringsOf(WidgetTester tester) =>
      AppLocalizations.of(tester.element(find.byType(SettingsScreen)));

  testWidgets('the settings show the real state of the synchronisation', (
    tester,
  ) async {
    useSurface(tester);
    final FakeSyncRepository repository = FakeSyncRepository(
      initialStatus: SyncStatus.synced,
    );
    addTearDown(repository.close);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [syncRepositoryProvider.overrideWithValue(repository)],
        child: harness(),
      ),
    );
    await tester.pumpAndSettle();
    final AppLocalizations strings = stringsOf(tester);

    expect(find.text(strings.syncStatusSynced), findsOneWidget);

    repository.emit(SyncStatus.conflict);
    await tester.pumpAndSettle();

    expect(find.text(strings.syncStatusConflict), findsOneWidget);
    expect(find.text(strings.syncStatusSynced), findsNothing);
  });

  testWidgets('the settings show the modifications waiting to be pushed', (
    tester,
  ) async {
    useSurface(tester);
    final FakeSyncRepository repository = FakeSyncRepository(
      initialStatus: SyncStatus.offline,
      pendingCount: 3,
    );
    addTearDown(repository.close);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [syncRepositoryProvider.overrideWithValue(repository)],
        child: harness(),
      ),
    );
    await tester.pumpAndSettle();
    final AppLocalizations strings = stringsOf(tester);

    expect(find.text(strings.syncStatusOffline(3)), findsOneWidget);
    expect(find.text(strings.syncPendingPlural(3)), findsOneWidget);
  });

  testWidgets('the theme selector really changes the theme', (tester) async {
    useSurface(tester);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          syncRepositoryProvider.overrideWithValue(FakeSyncRepository()),
        ],
        child: harness(),
      ),
    );
    await tester.pumpAndSettle();
    final AppLocalizations strings = stringsOf(tester);

    final Finder night = find.text(strings.settingsThemeNight);
    await tester.ensureVisible(night);
    await tester.tap(night);
    await tester.pumpAndSettle();

    final ProviderContainer container = ProviderScope.containerOf(
      tester.element(find.byType(SettingsScreen)),
    );
    expect(container.read(themeControllerProvider), LimpidThemeVariant.night);
    expect(
      Theme.of(tester.element(find.byType(SettingsScreen))).brightness,
      Brightness.dark,
    );
  });

  testWidgets('the sign out button signs the author out', (tester) async {
    useSurface(tester);
    final FakeAuthRepository auth = FakeAuthRepository();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authRepositoryProvider.overrideWithValue(auth),
          sessionControllerProvider.overrideWith(
            (Ref ref) => Stream<AuthSession?>.value(
              const AuthSession(
                userId: 'author-1',
                email: 'auteur@exemple.fr',
                authorName: 'Aurélien Sandre',
              ),
            ),
          ),
        ],
        child: harness(),
      ),
    );
    await tester.pumpAndSettle();
    final AppLocalizations strings = stringsOf(tester);

    expect(find.text('Aurélien Sandre'), findsOneWidget);
    expect(
      find.text(strings.settingsSignedInAs('auteur@exemple.fr')),
      findsOneWidget,
    );

    final Finder signOut = find.widgetWithText(
      LimpidButton,
      strings.actionSignOut,
    );
    await tester.ensureVisible(signOut);
    await tester.tap(signOut);
    await tester.pumpAndSettle();

    // La déconnexion demande d'abord ce que l'auteur veut faire des
    // données locales du compte.
    final Finder keep = find.widgetWithText(
      LimpidButton,
      strings.settingsEraseLocalDataKeep,
    );
    await tester.tap(keep);
    await tester.pumpAndSettle();

    expect(auth.signOutCalls, 1);
  });

  testWidgets('the export calls the repository and shows the produced file', (
    tester,
  ) async {
    useSurface(tester);
    final FakeManuscriptRepository manuscripts = FakeManuscriptRepository(
      projects: <Project>[
        const Project(
          id: ProjectId('project-1'),
          ownerId: AuthorId('test-author'),
          title: 'Le livre des matins',
          synopsis: 'Un synopsis.',
          order: OrderKey.initial,
        ),
      ],
    );
    final FakeExportRepository exports = FakeExportRepository();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          manuscriptRepositoryProvider.overrideWithValue(manuscripts),
          exportRepositoryProvider.overrideWithValue(exports),
        ],
        child: harness(),
      ),
    );
    await tester.pumpAndSettle();
    final AppLocalizations strings = stringsOf(tester);

    final Finder export = find.text(strings.settingsExportPersonalData);
    await tester.ensureVisible(export);
    await tester.tap(export);
    await tester.pumpAndSettle();

    expect(find.byType(LimpidDialog), findsOneWidget);

    await tester.tap(find.text('Le livre des matins'));
    await tester.pumpAndSettle();

    expect(exports.exports, hasLength(1));
    expect(exports.exports.single.projectId, 'project-1');
    expect(exports.exports.single.format, ExportFormat.markdown);
    expect(find.text('livre.md'), findsOneWidget);
  });
}
