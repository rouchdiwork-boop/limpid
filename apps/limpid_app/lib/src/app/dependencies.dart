import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:limpid_app/src/auth/auth_runtime.dart';
import 'package:limpid_app/src/bootstrap/app_bootstrap.dart';
import 'package:limpid_app/src/data/api_ai_repository.dart';
import 'package:limpid_app/src/data/api_client.dart';
import 'package:limpid_app/src/data/api_export_repository.dart';
import 'package:limpid_app/src/data/api_gdpr_repository.dart';
import 'package:limpid_app/src/data/api_plan_repository.dart';
import 'package:limpid_app/src/data/api_publication_repository.dart';
import 'package:limpid_app/src/data/app_database.dart';
import 'package:limpid_app/src/data/local_manuscript_repository.dart';
import 'package:limpid_app/src/data/local_preferences_repository.dart';
import 'package:limpid_app/src/data/local_publication_repository.dart';
import 'package:limpid_app/src/data/local_revision_repository.dart';
import 'package:limpid_app/src/data/local_sync_repository.dart';
import 'package:limpid_app/src/data/project_identity_store.dart';
import 'package:limpid_app/src/data/project_ops_transport.dart';
import 'package:limpid_app/src/domain/fallbacks.dart';
import 'package:limpid_app/src/domain/gdpr_repository.dart';
import 'package:limpid_app/src/domain/plan_repository.dart';
import 'package:limpid_app/src/domain/providers.dart';
import 'package:limpid_app/src/domain/publication_repository.dart';
import 'package:limpid_app/src/domain/repositories.dart';
import 'package:limpid_app/src/domain/revision_repository.dart';
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
    required this.plans,
    required this.localDataEraser,
    required this.author,
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

  /// The subscription, the quotas and the payment of the author.
  final PlanRepository plans;

  /// The erasure of the local data of the author (D-19).
  final LocalDataEraser localDataEraser;

  /// The author stamping the local operations.
  final AuthorId author;

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
  final http.Client httpClient = http.Client();
  final Uri baseUrl = Uri.parse(apiBaseUrl);
  final ApiClient apiClient = ApiClient(
    baseUrl: baseUrl,
    client: httpClient,
    tokenProvider: _accessToken,
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
      plans: plans,
      // Aucune base locale : rien à effacer, l'interface le dit.
      localDataEraser: _refuseTheErasure,
      author: author,
      close: () async => httpClient.close(),
    );
  }

  final AppDatabase opened = database;
  final LocalManuscriptRepository manuscripts = LocalManuscriptRepository(
    database: opened,
    author: author,
  );

  return AppDependencies(
    manuscripts: manuscripts,
    sync: LocalSyncRepository(
      database: opened,
      transport: ProjectOpsTransport(
        baseUrl: baseUrl,
        client: httpClient,
        store: opened.manuscripts,
        // Le registre des identités : le serveur en fabrique un, l'appareil
        // l'adopte quand il diffère du sien.
        projects: ProjectIdentityStore(opened.sync, authorId: author.value),
        tokenProvider: _accessToken,
      ),
      author: author,
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
    plans: plans,
    localDataEraser: opened.wiper.wipe,
    author: author,
    close: () async {
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
