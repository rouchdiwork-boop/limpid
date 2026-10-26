import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:limpid_app/l10n/generated/app_localizations.dart';
import 'package:limpid_app/src/domain/admin_repository.dart';
import 'package:limpid_app/src/domain/plan_repository.dart';
import 'package:limpid_app/src/domain/providers.dart';
import 'package:limpid_app/src/features/admin/admin_account_screen.dart';
import 'package:limpid_app/src/features/admin/admin_routes.dart';
import 'package:limpid_app/src/features/admin/admin_screen.dart';
import 'package:limpid_design_system/limpid_design_system.dart';

import 'fakes.dart';

/// Gives the test a viewport of the size it needs.
void useSurface(WidgetTester tester, Size size) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

/// Builds the back-office screen of the test.
///
/// The back-office port and the plan port are the only things the screen
/// reads: the fakes are enough. A repository of `null` leaves the port
/// unwired, as it is before the wave is composed.
Widget adminHarness({AdminRepository? repository, PlanRepository? plans}) {
  return ProviderScope(
    overrides: [
      if (repository != null)
        adminRepositoryProvider.overrideWithValue(repository),
      planRepositoryProvider.overrideWithValue(plans ?? FakePlanRepository()),
    ],
    child: MaterialApp.router(
      theme: LimpidTheme.of(LimpidThemeVariant.paper),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      routerConfig: adminRouter(),
    ),
  );
}

/// The router the test navigates with.
///
/// The routes are the ones the screen asks for: the router of the
/// application declares them when the wave is composed.
GoRouter adminRouter() {
  return GoRouter(
    initialLocation: AdminRoutes.list,
    routes: <RouteBase>[
      GoRoute(
        path: AdminRoutes.list,
        builder: (BuildContext context, GoRouterState state) =>
            const AdminScreen(),
        routes: <RouteBase>[
          GoRoute(
            path: '${AdminRoutes.accountSegment}/:userId',
            builder: (BuildContext context, GoRouterState state) =>
                AdminAccountScreen(
                  accountId: state.pathParameters['userId'] ?? '',
                ),
          ),
        ],
      ),
    ],
  );
}

/// The strings of the back-office screen.
AppLocalizations adminStrings(WidgetTester tester) =>
    AppLocalizations.of(tester.element(find.byType(AdminScreen)));

/// The strings of the page of a account.
AppLocalizations adminAccountStrings(WidgetTester tester) =>
    AppLocalizations.of(tester.element(find.byType(AdminAccountScreen)));
