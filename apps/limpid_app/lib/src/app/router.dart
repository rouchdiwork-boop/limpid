import 'package:go_router/go_router.dart';
import 'package:limpid_app/src/auth/auth_repository.dart';
import 'package:limpid_app/src/auth/session_controller.dart';
import 'package:limpid_app/src/domain/providers.dart';
import 'package:limpid_app/src/features/admin/admin_account_screen.dart';
import 'package:limpid_app/src/features/admin/admin_routes.dart';
import 'package:limpid_app/src/features/admin/admin_screen.dart';
import 'package:limpid_app/src/features/auth/screens/sign_in_screen.dart';
import 'package:limpid_app/src/features/auth/screens/sign_up_screen.dart';
import 'package:limpid_app/src/features/billing/billing_routes.dart';
import 'package:limpid_app/src/features/billing/billing_screen.dart';
import 'package:limpid_app/src/features/dashboard/dashboard_screen.dart';
import 'package:limpid_app/src/features/library/library_screen.dart';
import 'package:limpid_app/src/features/onboarding/onboarding_screen.dart';
import 'package:limpid_app/src/features/project/project_picker_screen.dart';
import 'package:limpid_app/src/features/project/project_screen.dart';
import 'package:limpid_app/src/features/publication/kdp/kdp_screen.dart';
import 'package:limpid_app/src/features/publication/kdp/kdp_submission_screen.dart';
import 'package:limpid_app/src/features/publication/publication_author_screen.dart';
import 'package:limpid_app/src/features/publication/publication_reader.dart';
import 'package:limpid_app/src/features/publication/publication_routes.dart';
import 'package:limpid_app/src/features/publication/publication_screen.dart';
import 'package:limpid_app/src/features/publication/purchases/purchases_routes.dart';
import 'package:limpid_app/src/features/publication/purchases/purchases_screen.dart';
import 'package:limpid_app/src/features/publication/sale/book_sale_screen.dart';
import 'package:limpid_app/src/features/publication/sale/payment_return_screen.dart';
import 'package:limpid_app/src/features/revision/history/history_routes.dart';
import 'package:limpid_app/src/features/revision/history/history_screen.dart';
import 'package:limpid_app/src/features/search/search_screen.dart';
import 'package:limpid_app/src/features/security/two_factor_screen.dart';
import 'package:limpid_app/src/features/settings/settings_screen.dart';
import 'package:limpid_app/src/features/teams/team_detail_screen.dart';
import 'package:limpid_app/src/features/teams/teams_routes.dart';
import 'package:limpid_app/src/features/teams/teams_screen.dart';
import 'package:limpid_app/src/features/webhooks/api_keys_screen.dart';
import 'package:limpid_app/src/features/webhooks/webhook_deliveries_screen.dart';
import 'package:limpid_app/src/features/webhooks/webhooks_screen.dart';
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
      location.startsWith(PublicationRoutes.authorPrefix) ||
      location.startsWith(PublicationRoutes.salePrefix) ||
      location.startsWith(PublicationRoutes.paymentReturnPrefix);
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

  /// The second factor of the account.
  static const String twoFactor = '$settings/double-authentification';

  /// The segment of the second factor, relatif aux reglages.
  static const String twoFactorSegment = 'double-authentification';

  /// The API keys of the account.
  static const String apiKeys = '$settings/cles-api';

  /// The segment of the API keys, relatif aux reglages.
  static const String apiKeysSegment = 'cles-api';

  /// The outgoing webhooks of the account.
  static const String webhooks = '$settings/webhooks';

  /// The segment of the webhooks, relatif aux reglages.
  static const String webhooksSegment = 'webhooks';

  /// The deliveries of the webhooks.
  static const String webhookDeliveries = '$webhooks/livraisons';

  /// The segment of the deliveries, relatif aux webhooks.
  static const String webhookDeliveriesSegment = 'livraisons';

  /// The teams of the author.
  static const String teams = TeamsRoutes.list;

  /// The segment of the teams, relatif a la bibliotheque.
  static const String teamsSegment = TeamsRoutes.segment;

  /// The back-office of the service.
  static const String admin = '$settings/${AdminRoutes.segment}';

  /// The segment of the back-office, relatif aux reglages.
  static const String adminSegment = AdminRoutes.segment;

  /// The Amazon KDP submissions of the author.
  static const String kdp = '$library/kdp';

  /// The segment of the KDP, relatif a la bibliotheque.
  static const String kdpSegment = 'kdp';

  /// The search in the books of the author.
  static const String search = '$library/recherche';

  /// The segment of the search, relatif a la bibliotheque.
  static const String searchSegment = 'recherche';

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
    // La cle de navigation est celle de la composition racine : les
    // lectures distantes s'en servent pour ouvrir la fenetre du second
    // facteur, et n'ont pas de `BuildContext` propre.
    navigatorKey: ref.read(navigatorKeyProvider),
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
      // La page de vente et le retour du paiement sont publics comme la
      // vitrine : un lecteur ouvre la page d'un livre, il ne se connecte
      // pas pour la voir.
      GoRoute(
        path: PublicationRoutes.salePattern,
        builder: (context, state) =>
            BookSaleScreen(projectId: state.pathParameters['projectId'] ?? ''),
      ),
      GoRoute(
        path: PublicationRoutes.paymentReturnPattern,
        builder: (context, state) => PaymentReturnScreen(
          projectId: state.pathParameters['projectId'] ?? '',
        ),
      ),
      // L'historique des versions porte sur un document : il a son propre
      // chemin, comme les pages publiques d'un livre.
      GoRoute(
        path: HistoryRoutes.detailPattern,
        builder: (context, state) =>
            HistoryScreen(documentId: state.pathParameters['documentId'] ?? ''),
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
                routes: <RouteBase>[
                  // Les livres achetés sont une page du compte : elle
                  // accompagne la bibliotheque, d'ou l'auteur y trouve
                  // deja ses livres.
                  GoRoute(
                    path: PurchasesRoutes.segment,
                    builder: (context, state) => const PurchasesScreen(),
                  ),
                  // Les depots chez Amazon sont une page de l'auteur :
                  // ils vivent dans la branche de la bibliotheque, comme
                  // le reste de ce qui porte sur ses livres.
                  GoRoute(
                    path: AppRoutes.kdpSegment,
                    builder: (context, state) => const KdpScreen(),
                    routes: <RouteBase>[
                      GoRoute(
                        path: ':submissionId',
                        builder: (context, state) => KdpSubmissionScreen(
                          submissionId:
                              state.pathParameters['submissionId'] ?? '',
                        ),
                      ),
                    ],
                  ),
                  GoRoute(
                    path: AppRoutes.teamsSegment,
                    builder: (context, state) => const TeamsScreen(),
                    routes: <RouteBase>[
                      GoRoute(
                        path: ':teamId',
                        builder: (context, state) => TeamDetailScreen(
                          teamId: state.pathParameters['teamId'] ?? '',
                        ),
                      ),
                    ],
                  ),
                  // La recherche porte sur tous les livres de l'auteur :
                  // elle vit dans la bibliotheque, d'ou elle part.
                  GoRoute(
                    path: AppRoutes.searchSegment,
                    builder: (context, state) => const SearchScreen(),
                  ),
                ],
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
                routes: <RouteBase>[
                  GoRoute(
                    path: AppRoutes.twoFactorSegment,
                    builder: (context, state) => const TwoFactorScreen(),
                  ),
                  // Les cles d'API et les points de rappel sont des
                  // reglages du compte : ils vivent avec le reste.
                  GoRoute(
                    path: AppRoutes.apiKeysSegment,
                    builder: (context, state) => const ApiKeysScreen(),
                  ),
                  // Le back-office est une page de l'administration : elle
                  // vit avec les reglages, comme le second facteur.
                  GoRoute(
                    path: AppRoutes.adminSegment,
                    builder: (context, state) => const AdminScreen(),
                    routes: <RouteBase>[
                      GoRoute(
                        path: '${AdminRoutes.accountSegment}/:userId',
                        builder: (context, state) => AdminAccountScreen(
                          accountId: state.pathParameters['userId'] ?? '',
                        ),
                      ),
                    ],
                  ),
                  GoRoute(
                    path: AppRoutes.webhooksSegment,
                    builder: (context, state) => const WebhooksScreen(),
                    routes: <RouteBase>[
                      GoRoute(
                        path: AppRoutes.webhookDeliveriesSegment,
                        builder: (context, state) =>
                            const WebhookDeliveriesScreen(),
                      ),
                    ],
                  ),
                ],
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
