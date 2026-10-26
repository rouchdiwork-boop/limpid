import 'package:flutter/foundation.dart';
import 'package:limpid_app/src/domain/repositories.dart';
import 'package:limpid_app/src/features/projects/project_cover.dart';
import 'package:limpid_app/src/features/projects/project_summary.dart';
import 'package:limpid_core/limpid_core.dart';

/// The library of the author, as the interface reads it.
///
/// It carries the projects with their figures **and** the scenes they are
/// made of: the dashboard reads the scenes to know what was written and
/// when.
@immutable
class LibrarySnapshot {
  /// Creates a snapshot.
  const LibrarySnapshot({required this.projects, required this.scenes});

  /// An empty library.
  static const LibrarySnapshot empty = LibrarySnapshot(
    projects: <ProjectSummary>[],
    scenes: <Scene>[],
  );

  /// The projects of the author, with their figures.
  final List<ProjectSummary> projects;

  /// Every scene of the library.
  final List<Scene> scenes;

  /// The number of projects in the library.
  int get projectCount => projects.length;

  /// The number of projects in the given editorial stage.
  int countByStatus(ManuscriptStatus status) => projects
      .where((ProjectSummary project) => project.status == status)
      .length;
}

/// Loads the library of the author from the repository.
///
/// Every figure of the library is read from the device: the chapters of each
/// project, then the scenes of each chapter. The word count of a book is the
/// sum of the words of its scenes.
Future<LibrarySnapshot> loadLibrary(ManuscriptRepository repository) async {
  final List<Project> projects = await repository.listProjects();
  final List<ProjectSummary> summaries = <ProjectSummary>[];
  final List<Scene> scenes = <Scene>[];

  for (final Project project in projects) {
    final List<Chapter> chapters = await repository.listChapters(
      project.id.value,
    );
    final List<Scene> projectScenes = <Scene>[];
    for (final Chapter chapter in chapters) {
      projectScenes.addAll(await repository.listScenes(chapter.id.value));
    }
    scenes.addAll(projectScenes);
    summaries.add(
      summarizeProject(
        project: project,
        chapters: chapters,
        scenes: projectScenes,
      ),
    );
  }

  return LibrarySnapshot(
    projects: List<ProjectSummary>.unmodifiable(summaries),
    scenes: List<Scene>.unmodifiable(scenes),
  );
}

/// Builds the view of a project from its chapters and its scenes.
///
/// The target of the book is the sum of the targets of its chapters; when no
/// chapter carries a target, the targets of the scenes are used instead.
///
/// The number of readings stays at zero: the local contract of the
/// manuscripts does not carry the counters of the public page yet, and a
/// figure that is invented would be worse than an honest zero.
ProjectSummary summarizeProject({
  required Project project,
  required List<Chapter> chapters,
  required List<Scene> scenes,
}) {
  final int words = scenes.fold<int>(
    0,
    (int total, Scene scene) => total + scene.wordCount,
  );
  final int chapterTarget = chapters.fold<int>(
    0,
    (int total, Chapter chapter) => total + chapter.targetWordCount,
  );
  final int sceneTarget = scenes.fold<int>(
    0,
    (int total, Scene scene) => total + scene.targetWordCount,
  );

  return ProjectSummary(
    project: project,
    wordCount: words,
    targetWordCount: chapterTarget > 0 ? chapterTarget : sceneTarget,
    chapterCount: chapters.length,
    sceneCount: scenes.length,
    readings: 0,
    coverSeed: coverSeedOf(project.id.value),
  );
}

/// The palette of the cover of a book, derived from its identifier.
///
/// The seed is stable: a book keeps its colour between two launches of the
/// application.
int coverSeedOf(String projectId) {
  int hash = 0;
  for (final int code in projectId.codeUnits) {
    hash = (hash * 31 + code) & 0x7fffffff;
  }
  return hash % ProjectCover.paletteCount;
}

/// The project the author is working on.
///
/// The manuscript in the `writing` stage comes first; when no manuscript is
/// being written, the most recently updated project is the current one.
ProjectSummary? currentProjectOf(List<ProjectSummary> projects) {
  for (final ProjectSummary project in projects) {
    if (project.status == ManuscriptStatus.writing) {
      return project;
    }
  }
  return projects.isEmpty ? null : projects.first;
}
