import 'package:limpid_core/src/domain/ids.dart';

/// The writing progress of a scene.
final class SceneProgress {
  /// Creates a scene progress.
  const SceneProgress({
    required this.wordCount,
    required this.targetWordCount,
    this.sceneId,
  });

  /// The scene this progress belongs to.
  final SceneId? sceneId;

  /// The number of words written in the scene.
  final int wordCount;

  /// The word count targeted for the scene.
  final int targetWordCount;

  /// The completion ratio, in `[0, 1]`.
  double get ratio {
    if (targetWordCount <= 0) return 0;
    return (wordCount / targetWordCount).clamp(0.0, 1.0);
  }

  /// Whether the scene reached its target.
  bool get isCompleted => targetWordCount > 0 && wordCount >= targetWordCount;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SceneProgress &&
          other.sceneId == sceneId &&
          other.wordCount == wordCount &&
          other.targetWordCount == targetWordCount);

  @override
  int get hashCode =>
      Object.hash(SceneProgress, sceneId, wordCount, targetWordCount);

  @override
  String toString() => 'SceneProgress($wordCount/$targetWordCount)';
}

/// The writing progress of a chapter, aggregated from its scenes.
final class ChapterProgress {
  /// Creates a chapter progress.
  const ChapterProgress({
    required this.wordCount,
    required this.targetWordCount,
    required this.sceneCount,
    required this.completedSceneCount,
    this.chapterId,
  });

  /// The chapter this progress belongs to.
  final ChapterId? chapterId;

  /// The total number of words of the chapter.
  final int wordCount;

  /// The word count targeted for the chapter.
  final int targetWordCount;

  /// The number of scenes of the chapter.
  final int sceneCount;

  /// The number of scenes that reached their target.
  final int completedSceneCount;

  /// The completion ratio, in `[0, 1]`.
  double get ratio {
    if (targetWordCount <= 0) return 0;
    return (wordCount / targetWordCount).clamp(0.0, 1.0);
  }

  /// Whether the chapter reached its target.
  bool get isCompleted => targetWordCount > 0 && wordCount >= targetWordCount;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ChapterProgress &&
          other.chapterId == chapterId &&
          other.wordCount == wordCount &&
          other.targetWordCount == targetWordCount &&
          other.sceneCount == sceneCount &&
          other.completedSceneCount == completedSceneCount);

  @override
  int get hashCode => Object.hash(
    ChapterProgress,
    chapterId,
    wordCount,
    targetWordCount,
    sceneCount,
    completedSceneCount,
  );

  @override
  String toString() => 'ChapterProgress($wordCount/$targetWordCount)';
}

/// The writing progress of a volume, aggregated from its chapters.
final class VolumeProgress {
  /// Creates a volume progress.
  const VolumeProgress({
    required this.wordCount,
    required this.targetWordCount,
    required this.chapterCount,
    required this.completedChapterCount,
    this.volumeId,
  });

  /// The volume this progress belongs to.
  final VolumeId? volumeId;

  /// The total number of words of the volume.
  final int wordCount;

  /// The word count targeted for the volume.
  final int targetWordCount;

  /// The number of chapters of the volume.
  final int chapterCount;

  /// The number of chapters that reached their target.
  final int completedChapterCount;

  /// The completion ratio, in `[0, 1]`.
  double get ratio {
    if (targetWordCount <= 0) return 0;
    return (wordCount / targetWordCount).clamp(0.0, 1.0);
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is VolumeProgress &&
          other.volumeId == volumeId &&
          other.wordCount == wordCount &&
          other.targetWordCount == targetWordCount &&
          other.chapterCount == chapterCount &&
          other.completedChapterCount == completedChapterCount);

  @override
  int get hashCode => Object.hash(
    VolumeProgress,
    volumeId,
    wordCount,
    targetWordCount,
    chapterCount,
    completedChapterCount,
  );

  @override
  String toString() => 'VolumeProgress($wordCount/$targetWordCount)';
}

/// The writing progress of a series, aggregated from its volumes.
final class SeriesProgress {
  /// Creates a series progress.
  const SeriesProgress({
    required this.wordCount,
    required this.targetWordCount,
    required this.volumeCount,
    required this.completedVolumeCount,
    this.seriesId,
  });

  /// The series this progress belongs to.
  final SeriesId? seriesId;

  /// The total number of words of the series.
  final int wordCount;

  /// The word count targeted for the series.
  final int targetWordCount;

  /// The number of volumes of the series.
  final int volumeCount;

  /// The number of volumes that reached their target.
  final int completedVolumeCount;

  /// The completion ratio, in `[0, 1]`.
  double get ratio {
    if (targetWordCount <= 0) return 0;
    return (wordCount / targetWordCount).clamp(0.0, 1.0);
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SeriesProgress &&
          other.seriesId == seriesId &&
          other.wordCount == wordCount &&
          other.targetWordCount == targetWordCount &&
          other.volumeCount == volumeCount &&
          other.completedVolumeCount == completedVolumeCount);

  @override
  int get hashCode => Object.hash(
    SeriesProgress,
    seriesId,
    wordCount,
    targetWordCount,
    volumeCount,
    completedVolumeCount,
  );

  @override
  String toString() => 'SeriesProgress($wordCount/$targetWordCount)';
}

/// Aggregates writing progress along the editorial hierarchy (D-02).
///
/// The statistics are aggregated from the scene level up to the chapter, the
/// volume and the series.
final class ProgressCalculator {
  /// Creates a progress calculator.
  const ProgressCalculator();

  /// Builds the progress of a scene.
  SceneProgress forScene({
    required int wordCount,
    required int targetWordCount,
    SceneId? sceneId,
  }) {
    return SceneProgress(
      sceneId: sceneId,
      wordCount: wordCount,
      targetWordCount: targetWordCount,
    );
  }

  /// Builds the progress of a chapter from the progress of its scenes.
  ChapterProgress forChapter({
    required List<SceneProgress> scenes,
    int targetWordCount = 0,
    ChapterId? chapterId,
  }) {
    var words = 0;
    var completed = 0;
    for (final scene in scenes) {
      words += scene.wordCount;
      if (scene.isCompleted) completed++;
    }
    final target = targetWordCount > 0
        ? targetWordCount
        : scenes.fold<int>(0, (sum, scene) => sum + scene.targetWordCount);
    return ChapterProgress(
      chapterId: chapterId,
      wordCount: words,
      targetWordCount: target,
      sceneCount: scenes.length,
      completedSceneCount: completed,
    );
  }

  /// Builds the progress of a volume from the progress of its chapters.
  VolumeProgress forVolume({
    required List<ChapterProgress> chapters,
    int targetWordCount = 0,
    VolumeId? volumeId,
  }) {
    var words = 0;
    var completed = 0;
    for (final chapter in chapters) {
      words += chapter.wordCount;
      if (chapter.isCompleted) completed++;
    }
    final target = targetWordCount > 0
        ? targetWordCount
        : chapters.fold<int>(
            0,
            (sum, chapter) => sum + chapter.targetWordCount,
          );
    return VolumeProgress(
      volumeId: volumeId,
      wordCount: words,
      targetWordCount: target,
      chapterCount: chapters.length,
      completedChapterCount: completed,
    );
  }

  /// Builds the progress of a series from the progress of its volumes.
  SeriesProgress forSeries({
    required List<VolumeProgress> volumes,
    int targetWordCount = 0,
    SeriesId? seriesId,
  }) {
    var words = 0;
    var completed = 0;
    for (final volume in volumes) {
      words += volume.wordCount;
      if (volume.ratio >= 1) completed++;
    }
    final target = targetWordCount > 0
        ? targetWordCount
        : volumes.fold<int>(0, (sum, volume) => sum + volume.targetWordCount);
    return SeriesProgress(
      seriesId: seriesId,
      wordCount: words,
      targetWordCount: target,
      volumeCount: volumes.length,
      completedVolumeCount: completed,
    );
  }
}
