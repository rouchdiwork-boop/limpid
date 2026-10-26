import 'package:limpid_core/src/sync/order_key.dart';

import 'enums.dart';
import 'ids.dart';

/// The atomic unit of storage, synchronisation and versioning (D-02).
///
/// A scene owns exactly one CRDT [documentId]; the document holds the block
/// tree of the scene.
final class Scene {
  /// Creates a scene.
  const Scene({
    required this.id,
    required this.chapterId,
    required this.documentId,
    required this.title,
    required this.order,
    this.synopsis = '',
    this.status = ManuscriptStatus.draft,
    this.pointOfView,
    this.wordCount = 0,
    this.targetWordCount = 0,
    this.createdAt,
    this.updatedAt,
  });

  /// Identifier of the scene.
  final SceneId id;

  /// Chapter this scene belongs to.
  final ChapterId chapterId;

  /// CRDT document holding the blocks of this scene.
  final DocumentId documentId;

  /// Title of the scene.
  final String title;

  /// Short synopsis of the scene.
  final String synopsis;

  /// Editorial pipeline stage of the scene.
  final ManuscriptStatus status;

  /// Fractional index of the scene inside its chapter.
  final OrderKey order;

  /// Character whose point of view the scene is written from.
  final CharacterId? pointOfView;

  /// Number of words currently written in the scene.
  final int wordCount;

  /// Word count targeted for this scene, `0` when no target is set.
  final int targetWordCount;

  /// Creation timestamp.
  final DateTime? createdAt;

  /// Last modification timestamp.
  final DateTime? updatedAt;

  /// Whether the scene reaches its word count target.
  bool get hasReachedTarget =>
      targetWordCount > 0 && wordCount >= targetWordCount;

  /// Ratio of completion of the word count target, in `[0, 1]`.
  ///
  /// Returns `0` when no target is set.
  double get completionRatio {
    if (targetWordCount <= 0) return 0;
    return (wordCount / targetWordCount).clamp(0.0, 1.0);
  }

  /// Returns a copy of this scene with the given fields replaced.
  Scene copyWith({
    ChapterId? chapterId,
    String? title,
    String? synopsis,
    ManuscriptStatus? status,
    OrderKey? order,
    CharacterId? pointOfView,
    int? wordCount,
    int? targetWordCount,
    DateTime? updatedAt,
  }) {
    return Scene(
      id: id,
      chapterId: chapterId ?? this.chapterId,
      documentId: documentId,
      title: title ?? this.title,
      order: order ?? this.order,
      synopsis: synopsis ?? this.synopsis,
      status: status ?? this.status,
      pointOfView: pointOfView ?? this.pointOfView,
      wordCount: wordCount ?? this.wordCount,
      targetWordCount: targetWordCount ?? this.targetWordCount,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Scene &&
          other.id == id &&
          other.chapterId == chapterId &&
          other.documentId == documentId &&
          other.title == title &&
          other.synopsis == synopsis &&
          other.status == status &&
          other.order == order &&
          other.pointOfView == pointOfView &&
          other.wordCount == wordCount &&
          other.targetWordCount == targetWordCount &&
          other.createdAt == createdAt &&
          other.updatedAt == updatedAt);

  @override
  int get hashCode => Object.hash(
    Scene,
    id,
    chapterId,
    documentId,
    title,
    synopsis,
    status,
    order,
    pointOfView,
    wordCount,
    targetWordCount,
    createdAt,
    updatedAt,
  );

  @override
  String toString() => 'Scene($id, $title)';
}

/// Aggregated statistics over a set of scenes.
final class SceneStatistics {
  /// Creates a statistics snapshot.
  const SceneStatistics({required this.sceneCount, required this.wordCount});

  /// Empty statistics.
  static const SceneStatistics empty = SceneStatistics(
    sceneCount: 0,
    wordCount: 0,
  );

  /// Number of scenes.
  final int sceneCount;

  /// Total number of words.
  final int wordCount;

  /// Returns the sum of two statistics snapshots.
  SceneStatistics operator +(SceneStatistics other) => SceneStatistics(
    sceneCount: sceneCount + other.sceneCount,
    wordCount: wordCount + other.wordCount,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SceneStatistics &&
          other.sceneCount == sceneCount &&
          other.wordCount == wordCount);

  @override
  int get hashCode => Object.hash(SceneStatistics, sceneCount, wordCount);

  @override
  String toString() =>
      'SceneStatistics(scenes: $sceneCount, words: $wordCount)';
}

/// Computes aggregated statistics for a list of scenes.
///
/// The word counts are the ones carried by the scenes; the engine does not
/// need the block tree for that.
SceneStatistics computeSceneStatistics(List<Scene> scenes) {
  var words = 0;
  for (final scene in scenes) {
    words += scene.wordCount;
  }
  return SceneStatistics(sceneCount: scenes.length, wordCount: words);
}
