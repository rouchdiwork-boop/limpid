import 'package:flutter/foundation.dart';
import 'package:limpid_core/limpid_core.dart';

/// The presentation view of a project in the library and on the dashboard.
///
/// It gathers the figures the interface needs, computed with the rules of
/// `limpid_core` so that the client and the server agree on them.
///
/// The figures are never invented: they come from the chapters and the scenes
/// of the project, read from the `ManuscriptRepository`.
@immutable
class ProjectSummary {
  /// Creates the view.
  const ProjectSummary({
    required this.project,
    required this.wordCount,
    required this.targetWordCount,
    required this.chapterCount,
    required this.sceneCount,
    required this.readings,
    this.coverSeed = 0,
  });

  /// The underlying project.
  final Project project;

  /// The number of words written so far.
  final int wordCount;

  /// The number of words targeted.
  final int targetWordCount;

  /// The number of chapters.
  final int chapterCount;

  /// The number of scenes.
  final int sceneCount;

  /// The number of reads on the public page.
  final int readings;

  /// The index of the cover palette, used to give each book its own colour.
  final int coverSeed;

  /// The title of the project.
  String get title => project.title;

  /// The synopsis of the project.
  String get synopsis => project.synopsis;

  /// The editorial stage of the project.
  ManuscriptStatus get status => project.status;

  /// The completion ratio, between 0 and 1.
  double get progress =>
      targetWordCount <= 0 ? 0 : (wordCount / targetWordCount).clamp(0, 1);

  /// The completion ratio, as a whole percentage.
  int get progressPercent => (progress * 100).round();
}
