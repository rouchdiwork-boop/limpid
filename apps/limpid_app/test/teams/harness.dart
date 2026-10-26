import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:limpid_app/l10n/generated/app_localizations.dart';
import 'package:limpid_app/src/auth/auth_repository.dart';
import 'package:limpid_app/src/auth/session_controller.dart';
import 'package:limpid_app/src/domain/plan_repository.dart';
import 'package:limpid_app/src/domain/providers.dart';
import 'package:limpid_app/src/domain/team_repository.dart';
import 'package:limpid_app/src/features/teams/team_detail_screen.dart';
import 'package:limpid_app/src/features/teams/teams_routes.dart';
import 'package:limpid_app/src/features/teams/teams_screen.dart';
import 'package:limpid_design_system/limpid_design_system.dart';

import 'fakes.dart';

/// Gives the test a viewport of the size it needs.
void useSurface(WidgetTester tester, Size size) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

/// The session of the author of the test.
const AuthSession fakeSession = AuthSession(
  userId: 'owner-1',
  email: 'auteur@exemple.fr',
);

/// Builds the teams screen of the test.
///
/// The teams port, the plan port and the session are the only things the
/// screen reads: the fakes are enough.
Widget teamsHarness({
  required TeamRepository repository,
  PlanRepository? plans,
  AuthSession? session,
}) {
  return ProviderScope(
    overrides: [
      teamRepositoryProvider.overrideWithValue(repository),
      planRepositoryProvider.overrideWithValue(plans ?? FakePlanRepository()),
      sessionControllerProvider.overrideWith(
        (Ref ref) => Stream<AuthSession?>.value(session ?? fakeSession),
      ),
    ],
    child: MaterialApp.router(
      theme: LimpidTheme.of(LimpidThemeVariant.paper),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      // Les textes de l'ecran sont asserts en francais : la locale est
      // posee, sinon le poste de test choisirait l'anglais.
      locale: const Locale('fr'),
      routerConfig: teamsRouter(),
    ),
  );
}

/// Builds the page of a team of the test.
Widget teamDetailHarness({
  required TeamRepository repository,
  required String teamId,
  PlanRepository? plans,
  AuthSession? session,
}) {
  return ProviderScope(
    overrides: [
      teamRepositoryProvider.overrideWithValue(repository),
      planRepositoryProvider.overrideWithValue(plans ?? FakePlanRepository()),
      sessionControllerProvider.overrideWith(
        (Ref ref) => Stream<AuthSession?>.value(session ?? fakeSession),
      ),
    ],
    child: MaterialApp(
      theme: LimpidTheme.of(LimpidThemeVariant.paper),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      // Les textes de l'ecran sont asserts en francais : la locale est
      // posee, sinon le poste de test choisirait l'anglais.
      locale: const Locale('fr'),
      home: TeamDetailScreen(teamId: teamId),
    ),
  );
}

/// The router the test navigates with.
///
/// The routes are the ones the screen asks for : the routeur of the
/// application declares them when the wave is composed.
GoRouter teamsRouter() {
  return GoRouter(
    initialLocation: TeamsRoutes.list,
    routes: <RouteBase>[
      GoRoute(
        path: TeamsRoutes.list,
        builder: (BuildContext context, GoRouterState state) =>
            const TeamsScreen(),
      ),
      GoRoute(
        path: TeamsRoutes.detailPattern,
        builder: (BuildContext context, GoRouterState state) =>
            TeamDetailScreen(teamId: state.pathParameters['teamId'] ?? ''),
      ),
    ],
  );
}

/// The strings of the teams screen.
AppLocalizations teamsStrings(WidgetTester tester) =>
    AppLocalizations.of(tester.element(find.byType(TeamsScreen)));

/// The strings of the page of a team.
AppLocalizations teamStrings(WidgetTester tester) =>
    AppLocalizations.of(tester.element(find.byType(TeamDetailScreen)));
