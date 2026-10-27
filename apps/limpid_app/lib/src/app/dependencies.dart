import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:http/http.dart' as http;
import 'package:limpid_app/src/auth/auth_runtime.dart';
import 'package:limpid_app/src/auth/two_factor_proof_holder.dart';
import 'package:limpid_app/src/bootstrap/app_bootstrap.dart';
import 'package:limpid_app/src/data/api_admin_repository.dart';
import 'package:limpid_app/src/data/api_ai_consent_repository.dart';
import 'package:limpid_app/src/data/api_ai_repository.dart';
import 'package:limpid_app/src/data/api_book_sale_repository.dart';
import 'package:limpid_app/src/data/api_bundle_repository.dart';
import 'package:limpid_app/src/data/api_client.dart';
import 'package:limpid_app/src/data/api_export_repository.dart';
import 'package:limpid_app/src/data/api_gdpr_repository.dart';
import 'package:limpid_app/src/data/api_kdp_repository.dart';
import 'package:limpid_app/src/data/api_plan_repository.dart';
import 'package:limpid_app/src/data/api_publication_repository.dart';
import 'package:limpid_app/src/data/api_share_repository.dart';
import 'package:limpid_app/src/data/api_team_repository.dart';
import 'package:limpid_app/src/data/api_two_factor_repository.dart';
import 'package:limpid_app/src/data/api_webhook_repository.dart';
import 'package:limpid_app/src/data/app_database.dart';
import 'package:limpid_app/src/data/local_manuscript_repository.dart';
import 'package:limpid_app/src/data/local_preferences_repository.dart';
import 'package:limpid_app/src/data/local_publication_repository.dart';
import 'package:limpid_app/src/data/local_revision_repository.dart';
import 'package:limpid_app/src/data/local_search_repository.dart';
import 'package:limpid_app/src/data/local_sync_repository.dart';
import 'package:limpid_app/src/data/project_identity_store.dart';
import 'package:limpid_app/src/data/project_ops_transport.dart';
import 'package:limpid_app/src/data/real_time_transport.dart';
import 'package:limpid_app/src/domain/admin_repository.dart';
import 'package:limpid_app/src/domain/ai_consent_repository.dart';
import 'package:limpid_app/src/domain/book_sale_repository.dart';
import 'package:limpid_app/src/domain/bundle_repository.dart';
import 'package:limpid_app/src/domain/fallbacks.dart';
import 'package:limpid_app/src/domain/gdpr_repository.dart';
import 'package:limpid_app/src/domain/kdp_repository.dart';
import 'package:limpid_app/src/domain/plan_repository.dart';
import 'package:limpid_app/src/domain/providers.dart';
import 'package:limpid_app/src/domain/publication_repository.dart';
import 'package:limpid_app/src/domain/repositories.dart';
import 'package:limpid_app/src/domain/revision_repository.dart';
import 'package:limpid_app/src/domain/search_repository.dart';
import 'package:limpid_app/src/domain/share_repository.dart';
import 'package:limpid_app/src/domain/team_repository.dart';
import 'package:limpid_app/src/domain/two_factor_repository.dart';
import 'package:limpid_app/src/domain/webhook_repository.dart';
import 'package:limpid_app/src/features/settings/settings_providers.dart';
import 'package:limpid_core/limpid_core.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as sb;

/// The root of the API.
///
/// The address is supplied at build time with
/// `--dart-define=LIMPID_API_URL=https://api.limpid.app`. The default points
/// at the development server of the monorepo.
const String apiBaseUrl = String.fromEnvironment(
  'LIMPID_API_URL',
  defaultValue: 'http://localhost:8080',
);

/// The dependencies of the application.
///
/// They are built **once**, before the first frame, and given to the ports of
/// `lib/src/domain/providers.dart` through the overrides of the provider
/// scope. The screens never build anything themselves.
@immutable
final class AppDependencies {
  /// Creates the dependencies.
  const AppDependencies({
    required this.manuscripts,
    required this.sync,
    required this.preferences,
    required this.exports,
    required this.ai,
    required this.gdpr,
    required this.publication,
    required this.revision,
    required this.search,
    required this.admin,
    required this.plans,
    required this.twoFactor,
    required this.teams,
    required this.shares,
    required this.webhooks,
    required this.kdp,
    required this.sales,
    required this.aiConsents,
    required this.bundles,
    required this.localDataEraser,
    required this.author,
    required this.navigatorKey,
    required this.close,
  });

  /// The manuscripts of the author, served by the local database.
  final ManuscriptRepository manuscripts;

  /// The synchronisation of the local database with the server.
  final SyncRepository sync;

  /// The preferences of the author.
  final PreferencesRepository preferences;

  /// The exports of a manuscript.
  final ExportRepository exports;

  /// The assistant.
  final AiRepository ai;

  /// The personal data of the author (RGPD).
  final GdprRepository gdpr;

  /// The public page of the books of the showcase.
  final PublicationRepository publication;

  /// The discussions of the projects, held by the review.
  final RevisionRepository revision;

  /// The back-office of the service.
  ///
  /// The accounts and the feature flags are read on the server: they are
  /// the administrator's view of the service.
  final AdminRepository admin;

  /// The search in the manuscripts of the author.
  ///
  /// The search is **local** : it answers from the index of the device, and
  /// it never reaches the network.
  final SearchRepository search;

  /// The subscription, the quotas and the payment of the author.
  final PlanRepository plans;

  /// The second factor of the account.
  final TwoFactorRepository twoFactor;

  /// The teams of the account.
  final TeamRepository teams;

  /// The read-only shares of the account.
  final ShareRepository shares;

  /// The API keys and the webhooks of the account.
  final WebhookRepository webhooks;

  /// The Amazon KDP submissions of the account.
  final KdpRepository kdp;

  /// The sale of the books and the purchases of the account.
  final BookSaleRepository sales;

  /// The consent of the author to send their text to a third party.
  final AiConsentRepository aiConsents;

  /// The bundles of the books, and their purchase.
  final BundleRepository bundles;

  /// The erasure of the local data of the author (D-19).
  final LocalDataEraser localDataEraser;

  /// The author stamping the local operations.
  final AuthorId author;

  /// The navigation key of the application.
  ///
  /// The router uses it, and the remote reads use it to open the window of
  /// the second factor : a `FutureProvider` has no `BuildContext` of its
  /// own.
  final GlobalKey<NavigatorState> navigatorKey;

  /// Releases the resources held by the dependencies.
  final Future<void> Function() close;
}

/// Builds the dependencies of the application.
///
/// The local database is opened first: it is the source of truth of the
/// interface. When it cannot be opened — on the web without the WebAssembly
/// module of SQLite, for instance — the application falls back to the
/// in-memory repositories: the author can still write, and the interface
/// says that the manuscripts are not persisted.
Future<AppDependencies> buildAppDependencies() async {
  final AuthorId author = AuthorId(
    AuthRuntimeHolder.current.session?.userId ?? kLocalAuthorId,
  );
  // La cle de navigation est creee ici, une fois : le routeur s'en sert,
  // et les lectures distantes s'en servent pour ouvrir la fenetre du
  // second facteur.
  final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>(
    debugLabel: 'limpid',
  );
  final http.Client httpClient = http.Client();
  final Uri baseUrl = Uri.parse(apiBaseUrl);
  final ApiClient apiClient = ApiClient(
    baseUrl: baseUrl,
    client: httpClient,
    tokenProvider: _accessToken,
    // La preuve du second facteur est portée par la session : elle est
    // obtenue par l'écran, lue ici au moment de la requête. Le client
    // attend une fonction : la preuve change au cours de la session.
    twoFactorProof: () => TwoFactorProofHolder.currentValue,
  );

  // The personal data of the author lives on the server: the repository
  // exists as soon as a remote service is configured, whether or not the
  // local database could be opened.
  final GdprRepository gdpr = AppBootstrap.isSupabaseConfigured
      ? ApiGdprRepository(client: apiClient)
      : const UnavailableGdprRepository();

  // L'abonnement de l'auteur vit lui aussi sur le serveur. Le paiement ne
  // s'ouvre que lorsque l'application connaît son adresse publique : c'est
  // elle que le serveur utilise pour renvoyer l'auteur vers l'écran
  // d'abonnement après le paiement.
  final PlanRepository plans = AppBootstrap.isSupabaseConfigured
      ? ApiPlanRepository(client: apiClient, checkoutOrigin: _publicOrigin())
      : const UnavailablePlanRepository();

  // Le second facteur vit sur le serveur comme le reste : l'application
  // ne le calcule pas, elle demande un code et porte la preuve.
  final TwoFactorRepository twoFactor = AppBootstrap.isSupabaseConfigured
      ? ApiTwoFactorRepository(client: apiClient)
      : const UnavailableTwoFactorRepository();

  // Les equipes vivent sur le serveur : les sieges et les roles sont
  // compotes par le service, pas par l'appareil.
  final TeamRepository teams = AppBootstrap.isSupabaseConfigured
      ? ApiTeamRepository(client: apiClient)
      : const UnavailableTeamRepository();

  // Les partages en lecture vivent sur le serveur : le jeton secret
  // n'est montre qu'une fois, et il ne quitte jamais l'appareil.
  final ShareRepository shares = AppBootstrap.isSupabaseConfigured
      ? ApiShareRepository(client: apiClient)
      : const UnavailableShareRepository();

  // Les cles d'API et les points de rappel vivent sur le serveur : leurs
  // secrets ne quittent jamais le poste de l'auteur.
  final WebhookRepository webhooks = AppBootstrap.isSupabaseConfigured
      ? ApiWebhookRepository(client: apiClient)
      : const UnavailableWebhookRepository();

  // Les depots chez Amazon vivent sur le serveur : le dossier est prepare
  // et depose par l'API, l'application montre la trace.
  final KdpRepository kdp = AppBootstrap.isSupabaseConfigured
      ? ApiKdpRepository(client: apiClient)
      : const UnavailableKdpRepository();

  // Le back-office n'existe que sur un serveur configure : le mode
  // demonstration ne montre aucun compte.
  final AdminRepository admin = AppBootstrap.isSupabaseConfigured
      ? ApiAdminRepository(client: apiClient)
      : const UnavailableAdminRepository();

  // La vente d'un livre vit sur le serveur : le prix, la commande et les
  // achats y sont. Sans serveur, la page de vente dit que le livre n'est
  // pas en vente, et les achats refusent.
  final BookSaleRepository sales = AppBootstrap.isSupabaseConfigured
      ? ApiBookSaleRepository(
          client: apiClient,
          checkoutOrigin: _publicOrigin(),
        )
      : const UnavailableBookSaleRepository();

  // Le consentement a l'IA : l'assistant n'envoie rien tant que l'auteur
  // n'a pas accepte. Sans serveur, l'accord est retire.
  final AiConsentRepository aiConsents = AppBootstrap.isSupabaseConfigured
      ? ApiAiConsentRepository(client: apiClient)
      : const UnavailableAiConsentRepository();

  // Les bundles vivent sur le serveur, comme la vente : le prix du bundle
  // et les livres qui le composent y sont.
  final BundleRepository bundles = AppBootstrap.isSupabaseConfigured
      ? ApiBundleRepository(client: apiClient, checkoutOrigin: _publicOrigin())
      : const UnavailableBundleRepository();

  AppDatabase? database;
  try {
    database = await AppDatabase.open();
  } on Object catch (error) {
    debugPrint(
      'La base locale ne peut pas être ouverte ($error) : Limpid démarre '
      'sans persistance.',
    );
  }

  if (database == null) {
    final DemoManuscriptRepository manuscripts = DemoManuscriptRepository();
    return AppDependencies(
      manuscripts: manuscripts,
      sync: OfflineSyncRepository(),
      preferences: InMemoryPreferencesRepository(),
      exports: const UnavailableExportRepository(),
      ai: const UnavailableAiRepository(),
      gdpr: gdpr,
      publication: ApiPublicationRepository(
        client: apiClient,
        fallback: LocalPublicationRepository(manuscript: manuscripts),
      ),
      revision: InMemoryRevisionRepository(),
      // Sans base locale, il n'y a pas d'index a interroger : la
      // recherche refuse plutot que de dire que les livres sont vides.
      search: const UnavailableSearchRepository(),
      admin: admin,
      plans: plans,
      twoFactor: twoFactor,
      teams: teams,
      shares: shares,
      webhooks: webhooks,
      kdp: kdp,
      sales: sales,
      aiConsents: aiConsents,
      bundles: bundles,
      // Aucune base locale : rien à effacer, l'interface le dit.
      localDataEraser: _refuseTheErasure,
      author: author,
      navigatorKey: navigatorKey,
      close: () async => httpClient.close(),
    );
  }

  final AppDatabase opened = database;
  final LocalManuscriptRepository manuscripts = LocalManuscriptRepository(
    database: opened,
    author: author,
    // La lecture suit la **session vivante** : un compte qui se
    // connecte apres le demarrage trouve ses propres manuscrits, et ne
    // voit pas ceux du compte precedent.
    currentAuthor: () => AuthorId(opened.account.accountId),
  );

  // Le relais temps reel : la frappe distante et la presence. Il est un
  // **accélérateur**, jamais la source de verite : le push et le pull
  // restent sur le transport REST.
  final ProjectOpsTransport rest = ProjectOpsTransport(
    baseUrl: baseUrl,
    client: httpClient,
    store: opened.manuscripts,
    // Le registre des identités : le serveur en fabrique un, l'appareil
    // l'adopte quand il diffère du sien.
    projects: ProjectIdentityStore(opened.sync, authorId: author.value),
    tokenProvider: _accessToken,
    // La synchronisation atteint les routes protégées de l'API : elle
    // porte donc la preuve du second facteur, comme le client de l'API.
    twoFactorProof: () => TwoFactorProofHolder.currentValue,
  );
  final RealTimeTransport relay = RealTimeTransport(
    baseUrl: baseUrl,
    store: opened.manuscripts,
    rest: rest,
    tokenProvider: _accessToken,
    accountId: () => opened.account.accountId,
  );

  return AppDependencies(
    manuscripts: manuscripts,
    sync: LocalSyncRepository(
      database: opened,
      transport: rest,
      realTime: relay,
      author: author,
      currentAuthor: () => AuthorId(opened.account.accountId),
    ),
    preferences: LocalPreferencesRepository(database: opened),
    exports: ApiExportRepository(client: apiClient),
    ai: ApiAiRepository(client: apiClient),
    gdpr: gdpr,
    // La page publique d'un livre vient du serveur ; le manuscrit de
    // l'appareil prend le relais quand le serveur n'en publie pas ou
    // n'est pas joignable. L'application reste utilisable hors ligne.
    publication: ApiPublicationRepository(
      client: apiClient,
      fallback: LocalPublicationRepository(manuscript: manuscripts),
    ),
    revision: LocalRevisionRepository(database: opened),
    // La recherche suit la **session vivante** : elle porte les livres du
    // compte connecte, et rien d'autre.
    search: LocalSearchRepository(
      database: opened,
      currentAuthor: () => AuthorId(opened.account.accountId),
    ),
    admin: admin,
    plans: plans,
    twoFactor: twoFactor,
    teams: teams,
    shares: shares,
    webhooks: webhooks,
    kdp: kdp,
    sales: sales,
    aiConsents: aiConsents,
    bundles: bundles,
    localDataEraser: opened.wiper.wipe,
    author: author,
    navigatorKey: navigatorKey,
    close: () async {
      // Le relais se ferme avant la base : il tient des canaux ouverts sur
      // elle.
      await relay.dispose();
      await opened.close();
      httpClient.close();
    },
  );
}

/// The erasure of a build that holds no local database.
///
/// There is nothing to erase: the build has no local database. The port
/// refuses rather than pretend the data of the author was erased.
Future<void> _refuseTheErasure() => throw const ServiceUnavailableException();

/// The public origin of the application, when it knows it.
///
/// On the web, the address of the current page: the payment sends the author
/// back to the subscription screen. On the other platforms the application
/// does not know its public address — the payment service is then not
/// configured on this device, and the billing screen says so.
Uri? _publicOrigin() {
  if (!kIsWeb) return null;
  final Uri base = Uri.base;
  if (base.scheme.isEmpty || base.host.isEmpty) return null;
  return Uri(
    scheme: base.scheme,
    host: base.host,
    port: base.hasPort ? base.port : null,
  );
}

/// The bearer token of the current session.
///
/// It is resolved for every request: Supabase rotates it. It is `null` when
/// the application runs without a backend.
Future<String?> _accessToken() async {
  if (!AppBootstrap.isSupabaseConfigured) return null;
  return sb.Supabase.instance.client.auth.currentSession?.accessToken;
}
