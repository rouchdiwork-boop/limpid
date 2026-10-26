import 'package:go_router/go_router.dart';
import 'package:limpid_app/src/auth/auth_repository.dart';
import 'package:limpid_app/src/auth/session_controller.dart';
import 'package:limpid_app/src/features/auth/screens/sign_in_screen.dart';
import 'package:limpid_app/src/features/auth/screens/sign_up_screen.dart';
import 'package:limpid_app/src/features/billing/billing_routes.dart';
import 'package:limpid_app/src/features/billing/billing_screen.dart';
import 'package:limpid_app/src/features/dashboard/dashboard_screen.dart';
import 'package:limpid_app/src/features/library/library_screen.dart';
import 'package:limpid_app/src/features/onboarding/onboarding_screen.dart';
import 'package:limpid_app/src/features/project/project_picker_screen.dart';
import 'package:limpid_app/src/features/project/project_screen.dart';
import 'package:limpid_app/src/features/publication/publication_author_screen.dart';
import 'package:limpid_app/src/features/publication/publication_reader.dart';
import 'package:limpid_app/src/features/publication/publication_routes.dart';
import 'package:limpid_app/src/features/publication/publication_screen.dart';
import 'package:limpid_app/src/features/settings/settings_screen.dart';
import 'package:limpid_app/src/features/writing/writing_screen.dart';
import 'package:limpid_app/src/shell/app_shell.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'router.g.dart';

/// The routes reachable without being signed in.
const Set<String> _publicRoutes = <String>{'/connexion', '/inscription'};

/// Whether a path is a public page of a book.
///
/// The pages of the showcase are open to the readers of a book: they are not
/// pages an author works in, and they carry a path with a parameter, which
/// the set of the public routes cannot hold.
bool _isPublicLocation(String location) {
  if (_publicRoutes.contains(location)) return true;
  return location.startsWith(PublicationRoutes.showcasePrefix) ||
      location.startsWith(PublicationRoutes.readerPrefix) ||
      location.startsWith(PublicationRoutes.authorPrefix);
}

/// The routes of the signed-in part of the application.
abstract final class AppRoutes {
  /// The dashboard.
  static const String dashboard = '/bureau';

  /// The library of the author's projects.
  static const String library = '/bibliotheque';

  /// The onboarding wizard.
  static const String onboarding = '/onboarding';

  /// The sign-in screen.
  static const String signIn = '/connexion';

  /// The sign-up screen.
  static const String signUp = '/inscription';

  /// The settings.
  static const String settings = '/reglages';

  /// The subscription, the quotas and the invoices.
  static const String subscription = BillingRoutes.subscription;

  /// A single project.
  static String project(String projectId) => '/projets/$projectId';

  /// The writing screen of a project.
  static String writing(String projectId) => '/projets/$projectId/ecriture';
}

/// Builds the router of the application.
///
/// The router is created once and refreshed when the session changes, so that
/// the navigation stack survives a sign-in or a sign-out.
@Riverpod(keepAlive: true)
GoRouter appRouter(Ref ref) {
  final router = GoRouter(
    initialLocation: AppRoutes.dashboard,
    redirect: (context, state) {
      final session = ref.read(sessionControllerProvider).value;
      final location = state.matchedLocation;
      final isPublic = _isPublicLocation(location);

      if (session == null) {
        if (isPublic) return null;
        return AppRoutes.signIn;
      }
      if (location == AppRoutes.signIn || location == AppRoutes.signUp) {
        return AppRoutes.dashboard;
      }
      return null;
    },
    routes: <RouteBase>[
      GoRoute(
        path: AppRoutes.signIn,
        builder: (context, state) => const SignInScreen(),
      ),
      GoRoute(
        path: AppRoutes.signUp,
        builder: (context, state) => const SignUpScreen(),
      ),
      GoRoute(
        path: AppRoutes.onboarding,
        builder: (context, state) => const OnboardingScreen(),
      ),
      // The public pages of a book live outside the shell: a reader opens a
      // page, not the studio of an author.
      GoRoute(
        path: PublicationRoutes.showcasePattern,
        builder: (context, state) => PublicationScreen(
          projectId: state.pathParameters['projectId'] ?? '',
        ),
      ),
      GoRoute(
        path: PublicationRoutes.readerPattern,
        builder: (context, state) => PublicationReaderScreen(
          projectId: state.pathParameters['projectId'] ?? '',
        ),
      ),
      GoRoute(
        path: PublicationRoutes.authorPattern,
        builder: (context, state) => PublicationAuthorScreen(
          authorId: state.pathParameters['authorId'] ?? '',
        ),
      ),
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) =>
            AppShell(navigationShell: navigationShell),
        branches: <StatefulShellBranch>[
          StatefulShellBranch(
            routes: <RouteBase>[
              GoRoute(
                path: AppRoutes.dashboard,
                builder: (context, state) => const DashboardScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: <RouteBase>[
              GoRoute(
                path: AppRoutes.library,
                builder: (context, state) => const LibraryScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: <RouteBase>[
              GoRoute(
                path: '/projets',
                builder: (context, state) => const ProjectPickerScreen(),
              ),
              GoRoute(
                path: '/projets/:projectId',
                builder: (context, state) => ProjectScreen(
                  projectId: state.pathParameters['projectId'] ?? '',
                ),
              ),
              GoRoute(
                path: '/projets/:projectId/ecriture',
                builder: (context, state) => WritingScreen(
                  projectId: state.pathParameters['projectId'] ?? '',
                ),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: <RouteBase>[
              GoRoute(
                path: AppRoutes.settings,
                builder: (context, state) => const SettingsScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: <RouteBase>[
              GoRoute(
                path: AppRoutes.subscription,
                builder: (context, state) => const BillingScreen(),
              ),
            ],
          ),
        ],
      ),
    ],
  );

  ref.listen<AsyncValue<AuthSession?>>(
    sessionControllerProvider,
    (previous, next) => router.refresh(),
  );
  ref.onDispose(router.dispose);
  return router;
}
