import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:limpid_app/l10n/generated/app_localizations.dart';
import 'package:limpid_app/src/domain/kdp_repository.dart';
import 'package:limpid_app/src/domain/providers.dart';
import 'package:limpid_app/src/features/publication/kdp/kdp_routes.dart';
import 'package:limpid_app/src/features/publication/kdp/kdp_screen.dart';
import 'package:limpid_app/src/features/publication/kdp/kdp_submission_screen.dart';
import 'package:limpid_core/limpid_core.dart';
import 'package:limpid_design_system/limpid_design_system.dart';

import '../features/publication/fakes.dart';
import 'fakes.dart';

/// Le routeur de l'écran de publication.
///
/// Le routeur de l'application appartient à l'intégrateur : le test en
/// construit un qui déclare les mêmes chemins, pour montrer que les écrans
/// s'y adressent.
GoRouter kdpRouter({String initialLocation = KdpRoutes.screen}) {
  return GoRouter(
    initialLocation: initialLocation,
    routes: <RouteBase>[
      GoRoute(
        path: KdpRoutes.screen,
        builder: (BuildContext context, GoRouterState state) =>
            const KdpScreen(),
      ),
      GoRoute(
        path: KdpRoutes.submissionPattern,
        builder: (BuildContext context, GoRouterState state) =>
            KdpSubmissionScreen(
              submissionId: state.pathParameters['submissionId'] ?? '',
            ),
      ),
    ],
  );
}

/// Builds the publication screen of the test.
///
/// The port of the publication is the only thing the screens read: the fake
/// is enough.
Widget kdpHarness({
  required FakeKdpRepository repository,
  List<Project> books = const <Project>[],
  String location = KdpRoutes.screen,
}) {
  final GoRouter router = kdpRouter(initialLocation: location);
  addTearDown(router.dispose);
  return ProviderScope(
    overrides: [
      kdpRepositoryProvider.overrideWithValue(repository),
      manuscriptRepositoryProvider.overrideWithValue(
        FakePublicationRepository(projects: books),
      ),
    ],
    child: MaterialApp.router(
      theme: LimpidTheme.of(LimpidThemeVariant.paper),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      routerConfig: router,
    ),
  );
}

/// The strings of the publication screen.
AppLocalizations kdpStrings(WidgetTester tester) =>
    AppLocalizations.of(tester.element(find.byType(KdpScreen)));

/// The strings of the submission screen.
AppLocalizations submissionStrings(WidgetTester tester) =>
    AppLocalizations.of(tester.element(find.byType(KdpSubmissionScreen)));

/// Gives the test a viewport of the size it needs.
void useSurface(WidgetTester tester, Size size) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}
