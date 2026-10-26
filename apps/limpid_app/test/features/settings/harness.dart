import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:limpid_app/l10n/generated/app_localizations.dart';
import 'package:limpid_app/src/app/router.dart';
import 'package:limpid_app/src/app/theme_controller.dart';
import 'package:limpid_app/src/features/settings/settings_screen.dart';
import 'package:limpid_design_system/limpid_design_system.dart';

/// The application of the test: it follows the theme of the controller, as
/// the real application does.
class SettingsHarness extends ConsumerWidget {
  /// Creates the application of the test.
  const SettingsHarness({super.key, required this.router});

  /// The router of the test.
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

/// Gives the test a viewport large enough for the desktop layout.
///
/// The page is tall: every row of the settings is visible, and the tests
/// that tap one of them do not depend on the scroll position.
void useSurface(WidgetTester tester) {
  tester.view.physicalSize = const Size(1440, 2000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

/// Builds the settings screen of the test, inside a router.
Widget settingsHarness() {
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

  return SettingsHarness(router: router);
}

/// The strings of the settings screen.
AppLocalizations stringsOf(WidgetTester tester) =>
    AppLocalizations.of(tester.element(find.byType(SettingsScreen)));
