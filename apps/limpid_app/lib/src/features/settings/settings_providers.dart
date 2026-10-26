import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:limpid_app/src/domain/providers.dart';
import 'package:limpid_app/src/domain/repositories.dart';
import 'package:limpid_app/src/features/projects/projects_providers.dart';
import 'package:limpid_core/limpid_core.dart';

/// The light daily rhythm, in words.
const int lightDailyWordGoal = 500;

/// The regular daily rhythm, in words.
const int regularDailyWordGoal = 1500;

/// The intense daily rhythm, in words.
const int intenseDailyWordGoal = 3000;

/// The rhythms the author can choose from.
const List<int> dailyWordGoalChoices = <int>[
  lightDailyWordGoal,
  regularDailyWordGoal,
  intenseDailyWordGoal,
];

/// The daily rhythm of the author, in words.
///
/// The onboarding sets the rhythm, the settings screen reads it and lets the
/// author change it. The value lives in the session: it is not persisted yet,
/// the durable preference belongs to the session lot.
final dailyWordGoalProvider = NotifierProvider<DailyWordGoalNotifier, int>(
  DailyWordGoalNotifier.new,
);

/// Stores the daily rhythm of the author.
final class DailyWordGoalNotifier extends Notifier<int> {
  /// The rhythm used when the author never chose one.
  static const int defaultGoal = regularDailyWordGoal;

  @override
  int build() => defaultGoal;

  /// Sets a new rhythm.
  ///
  /// A rhythm of zero or less is ignored: the goal is a number of words.
  void set(int words) {
    if (words <= 0 || words == state) {
      return;
    }
    state = words;
  }
}

/// The state of the synchronisation, as the interface shows it.
///
/// The provider follows the stream of the repository and keeps the last known
/// status when the stream is silent.
final syncStatusProvider = StreamProvider<SyncStatus>((ref) {
  final SyncRepository repository = ref.watch(syncRepositoryProvider);
  return _watchStatus(repository);
});

/// The number of modifications waiting to be pushed to the server.
///
/// The contract does not expose the queue: the count is read from the
/// implementations that publish it and stays at zero for the others. It is
/// read again whenever the status of the synchronisation changes.
final pendingSyncCountProvider = Provider<int>((ref) {
  ref.watch(syncStatusProvider);
  final SyncRepository repository = ref.watch(syncRepositoryProvider);
  if (repository is PendingChangesSyncRepository) {
    return repository.pendingCount;
  }
  return 0;
});

/// The projects the author can export.
final libraryProjectsProvider = FutureProvider<List<Project>>((ref) async {
  final ManuscriptRepository repository = ref.watch(
    manuscriptRepositoryProvider,
  );
  return repository.listProjects();
});

/// The erasure of the local data of the author on the device.
///
/// The contract is a **function**: the screen knows it erases the local
/// data, it never knows how. The composition root hands it the
/// implementation of the data layer.
typedef LocalDataEraser = Future<void> Function();

/// The erasure of the local data of the author, wired by the composition
/// root.
///
/// The port is **not** wired by default: the default refuses the erasure
/// and says why. A build without a local database must never claim that the
/// data of the author was erased when nothing was erased.
final Provider<LocalDataEraser> localDataEraserProvider =
    Provider<LocalDataEraser>((Ref ref) => _unavailableEraser);

/// The eraser of a build that holds no local database.
Future<void> _unavailableEraser() => throw const ServiceUnavailableException();

/// Refreshes the screens that show the library of the author.
///
/// The wipe empties the local database: the library, the figures of the
/// dashboard and the preferences must show the empty state right away, and
/// never a manuscript that no longer exists.
void refreshLibraryProviders(WidgetRef ref) {
  ref.invalidate(libraryProjectsProvider);
  ref.invalidate(libraryProvider);
  ref.invalidate(dailyGoalProvider);
  ref.invalidate(streakProvider);
}

/// The state of the synchronisation action of the settings screen.
@immutable
class SyncActionState {
  /// Creates the state.
  const SyncActionState({this.isRunning = false, this.lastSynchronizedAt});

  /// Whether a synchronisation is running.
  final bool isRunning;

  /// When the last synchronisation succeeded, `null` when it never did.
  final DateTime? lastSynchronizedAt;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SyncActionState &&
          other.isRunning == isRunning &&
          other.lastSynchronizedAt == lastSynchronizedAt);

  @override
  int get hashCode => Object.hash(isRunning, lastSynchronizedAt);
}

/// Runs the synchronisation on demand.
final syncActionProvider =
    NotifierProvider<SyncActionNotifier, SyncActionState>(
      SyncActionNotifier.new,
    );

/// Runs the synchronisation and keeps the date of the last success.
final class SyncActionNotifier extends Notifier<SyncActionState> {
  @override
  SyncActionState build() => const SyncActionState();

  /// Pushes the pending operations and pulls the remote ones.
  ///
  /// The repository never throws by contract: an unreachable server leaves the
  /// status at `offline` and the date of the last success untouched.
  Future<void> synchronize() async {
    if (state.isRunning) {
      return;
    }
    state = SyncActionState(
      isRunning: true,
      lastSynchronizedAt: state.lastSynchronizedAt,
    );
    try {
      final SyncRepository repository = ref.read(syncRepositoryProvider);
      await repository.synchronize();
      final bool isOffline = repository.status == SyncStatus.offline;
      state = SyncActionState(
        isRunning: false,
        lastSynchronizedAt: isOffline
            ? state.lastSynchronizedAt
            : DateTime.now(),
      );
    } on Object {
      state = SyncActionState(
        isRunning: false,
        lastSynchronizedAt: state.lastSynchronizedAt,
      );
      rethrow;
    }
  }
}

Stream<SyncStatus> _watchStatus(SyncRepository repository) async* {
  yield repository.status;
  yield* repository.watch().distinct();
}
