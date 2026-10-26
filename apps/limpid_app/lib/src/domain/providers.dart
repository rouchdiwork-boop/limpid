import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:limpid_app/src/domain/fallbacks.dart';
import 'package:limpid_app/src/domain/gdpr_repository.dart';
import 'package:limpid_app/src/domain/repositories.dart';
import 'package:limpid_core/limpid_core.dart';

/// The identifier stamped on the operations while the session is unknown.
///
/// The author is not signed in yet — the application is in demo mode — the
/// operations are still local and must carry a stable author.
const String kLocalAuthorId = 'local-author';

/// The reasons why a remote action cannot be performed.
enum ServiceUnavailableReason {
  /// The build has no remote service configured.
  notConfigured,

  /// The author has no project the action could apply to.
  noProject,
}

/// Raised when an action needs a service this build does not provide.
///
/// The interface catches it to tell the author that the action is impossible,
/// instead of pretending that it succeeded.
final class ServiceUnavailableException implements Exception {
  /// Creates the exception.
  const ServiceUnavailableException({
    this.reason = ServiceUnavailableReason.notConfigured,
  });

  /// Why the service is unavailable.
  final ServiceUnavailableReason reason;

  @override
  String toString() => 'ServiceUnavailableException(${reason.name})';
}

/// A repository that cannot reach the backend.
///
/// The settings screen reads this marker to disable — and to explain — the
/// actions that would silently do nothing.
abstract interface class UnavailableService {}

/// A [SyncRepository] that knows the size of its pending queue.
///
/// The contract of `lib/src/domain/repositories.dart` does not expose the
/// queue. This optional capability lets the settings screen show the number
/// of waiting modifications when the implementation knows it, and keeps the
/// count at zero when it does not.
abstract interface class PendingChangesSyncRepository
    implements SyncRepository {
  /// The number of operations waiting to be pushed to the server.
  int get pendingCount;
}

/// The repository holding the manuscripts of the author.
///
/// The port is **not** wired by default: the implementation lives in the
/// data layer, and the composition root of the application overrides this
/// provider with it. Reading the provider without an override throws, which
/// keeps the screens from silently working on an empty manuscript.
final Provider<ManuscriptRepository> manuscriptRepositoryProvider =
    Provider<ManuscriptRepository>((Ref ref) {
      throw UnimplementedError(
        'The manuscript repository is not wired: override '
        '`manuscriptRepositoryProvider` with the implementation of the data '
        'layer.',
      );
    });

/// The repository driving the synchronisation of the manuscripts.
///
/// The composition root overrides it with the implementation of the data
/// layer. The default is the offline repository: a screen that reads it
/// without an override says the device is offline rather than failing.
final Provider<SyncRepository> syncRepositoryProvider =
    Provider<SyncRepository>((Ref ref) => OfflineSyncRepository());

/// The repository holding the preferences of the author.
///
/// The composition root overrides it with the implementation of the data
/// layer. The default keeps the preferences in the memory of the process.
final Provider<PreferencesRepository> preferencesRepositoryProvider =
    Provider<PreferencesRepository>(
      (Ref ref) => InMemoryPreferencesRepository(),
    );

/// The repository the exports of a manuscript go through.
///
/// The composition root overrides it with the implementation of the data
/// layer. The default refuses the export and says why: a screen must never
/// present a file that was never produced.
final Provider<ExportRepository> exportRepositoryProvider =
    Provider<ExportRepository>(
      (Ref ref) => const UnavailableExportRepository(),
    );

/// The repository answering the questions of the assistant.
///
/// The composition root overrides it with the implementation of the data
/// layer. The default says that the assistant is not configured.
final Provider<AiRepository> aiRepositoryProvider = Provider<AiRepository>((
  Ref ref,
) {
  return const UnavailableAiRepository();
});

/// The repository of the personal data of the author (RGPD).
///
/// The composition root overrides it with the implementation of the data
/// layer. The default refuses the export and the deletion and says why: the
/// settings screen must never claim that the data of the author was erased
/// when nothing was erased.
final Provider<GdprRepository> gdprRepositoryProvider =
    Provider<GdprRepository>((Ref ref) => const UnavailableGdprRepository());

/// The author stamping the operations produced by the editor.
///
/// The identifier comes from the session of the author. The screens do not
/// know the session themselves: the port is overridden by the composition
/// root of the application, which reads the identifier of the signed in
/// author. The default — a local identifier — keeps the editor usable when
/// nobody is signed in.
final Provider<AuthorId> authorIdProvider = Provider<AuthorId>((Ref ref) {
  return const AuthorId(kLocalAuthorId);
});
