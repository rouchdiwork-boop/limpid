import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:limpid_app/src/domain/providers.dart';
import 'package:limpid_app/src/domain/repositories.dart';
import 'package:limpid_app/src/features/projects/project_metrics.dart';
import 'package:limpid_app/src/features/projects/project_summary.dart';
import 'package:limpid_core/limpid_core.dart';

/// The moment the interface reads the figures of the day.
///
/// The provider is the seam of the clock: the tests fix the day they want to
/// read, the application reads the real one.
final todayProvider = Provider<DateTime>((ref) => DateTime.now());

/// The library of the author, read from the repository.
///
/// The figures of the library — the chapters, the scenes and the words they
/// hold — are computed by [loadLibrary] from the local database. The provider
/// is the single seam the data layer replaces.
final libraryProvider =
    AsyncNotifierProvider<LibraryController, LibrarySnapshot>(
      LibraryController.new,
    );

/// Loads the library of the author.
final class LibraryController extends AsyncNotifier<LibrarySnapshot> {
  @override
  Future<LibrarySnapshot> build() async {
    final ManuscriptRepository repository = ref.watch(
      manuscriptRepositoryProvider,
    );
    return loadLibrary(repository);
  }

  /// Writes a snapshot the caller has already read.
  ///
  /// The screens that change the library — the publication of a book — read
  /// it again themselves and write the snapshot they produced: the interface
  /// then shows the new state of the library, without the flash of loading
  /// that the invalidation of the provider would cause.
  void replace(LibrarySnapshot snapshot) {
    state = AsyncData(snapshot);
  }
}

/// The projects of the author, with the figures of their manuscripts.
///
/// The screens that read the library synchronously use this provider; the
/// screens that show the loading and the error states watch [libraryProvider]
/// and read the projects of its snapshot.
final projectsControllerProvider = Provider<List<ProjectSummary>>((ref) {
  return ref.watch(libraryProvider).value?.projects ?? const <ProjectSummary>[];
});

/// The project the author is working on, `null` when the library is empty.
final currentProjectProvider = Provider<ProjectSummary?>((ref) {
  return currentProjectOf(ref.watch(projectsControllerProvider));
});

/// The number of words the author aims to write every day.
final dailyGoalProvider = FutureProvider<int>((ref) async {
  final PreferencesRepository preferences = ref.watch(
    preferencesRepositoryProvider,
  );
  return preferences.dailyGoal();
});

/// The number of consecutive days on which the author wrote.
final streakProvider = FutureProvider<int>((ref) async {
  final PreferencesRepository preferences = ref.watch(
    preferencesRepositoryProvider,
  );
  return preferences.writingStreak();
});

/// The number of words the author wrote today.
///
/// The figure comes from the **sessions** of the writing: the words the
/// author added today, never the size of the chapters they touched. A book
/// that is re-read today was not written today.
final wordsWrittenTodayProvider = FutureProvider<int>((ref) async {
  final ManuscriptRepository repository = ref.watch(
    manuscriptRepositoryProvider,
  );
  if (repository is! WritingSessionRepository) return 0;
  final DateTime today = ref.watch(todayProvider);
  final List<WritingSession> sessions = await repository.writingSessions(
    from: today,
    to: today,
  );
  return sessions.fold<int>(
    0,
    (int total, WritingSession session) => total + session.words,
  );
});

/// The chapters of a project, with the number of words they hold.
///
/// The chapters come from the repository, and the figure of each one is the
/// sum of the words of its scenes.
final projectChaptersProvider =
    FutureProvider.family<List<(Chapter, int)>, String>((
      Ref ref,
      String projectId,
    ) async {
      final ManuscriptRepository repository = ref.watch(
        manuscriptRepositoryProvider,
      );
      final List<Chapter> chapters = await repository.listChapters(projectId);

      final List<(Chapter, int)> result = <(Chapter, int)>[];
      for (final Chapter chapter in chapters) {
        final List<Scene> scenes = await repository.listScenes(
          chapter.id.value,
        );
        final int words = scenes.fold<int>(
          0,
          (int total, Scene scene) => total + scene.wordCount,
        );
        result.add((chapter, words));
      }
      return List<(Chapter, int)>.unmodifiable(result);
    });
