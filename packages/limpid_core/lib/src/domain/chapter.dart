import 'package:limpid_core/src/internal/collections.dart';
import 'package:limpid_core/src/sync/order_key.dart';

import 'enums.dart';
import 'ids.dart';

/// The unit of publication: an ordered set of scenes.
///
/// The chapter is a *view* over scenes (D-02): it owns no text, only the
/// order of the scenes it contains.
final class Chapter {
  /// Creates a chapter.
  const Chapter({
    required this.id,
    required this.title,
    required this.order,
    this.volumeId,
    this.synopsis = '',
    this.status = ManuscriptStatus.draft,
    this.sceneIds = const <SceneId>[],
    this.targetWordCount = 0,
    this.createdAt,
    this.updatedAt,
  });

  /// Identifier of the chapter.
  final ChapterId id;

  /// Volume this chapter belongs to, `null` when the chapter sits directly
  /// under the project.
  final VolumeId? volumeId;

  /// Title of the chapter.
  final String title;

  /// Short synopsis of the chapter.
  final String synopsis;

  /// Editorial pipeline stage of the chapter.
  final ManuscriptStatus status;

  /// Fractional index of the chapter inside its parent.
  final OrderKey order;

  /// Ordered identifiers of the scenes of this chapter.
  final List<SceneId> sceneIds;

  /// Word count targeted for this chapter, `0` when no target is set.
  final int targetWordCount;

  /// Creation timestamp.
  final DateTime? createdAt;

  /// Last modification timestamp.
  final DateTime? updatedAt;

  /// Whether the chapter reaches its word count target.
  bool hasReachedTarget(int actualWordCount) =>
      targetWordCount > 0 && actualWordCount >= targetWordCount;

  /// Returns a copy of this chapter with the given fields replaced.
  Chapter copyWith({
    VolumeId? volumeId,
    String? title,
    String? synopsis,
    ManuscriptStatus? status,
    OrderKey? order,
    List<SceneId>? sceneIds,
    int? targetWordCount,
    DateTime? updatedAt,
  }) {
    return Chapter(
      id: id,
      title: title ?? this.title,
      order: order ?? this.order,
      volumeId: volumeId ?? this.volumeId,
      synopsis: synopsis ?? this.synopsis,
      status: status ?? this.status,
      sceneIds: sceneIds ?? this.sceneIds,
      targetWordCount: targetWordCount ?? this.targetWordCount,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Chapter &&
          other.id == id &&
          other.volumeId == volumeId &&
          other.title == title &&
          other.synopsis == synopsis &&
          other.status == status &&
          other.order == order &&
          other.targetWordCount == targetWordCount &&
          other.createdAt == createdAt &&
          other.updatedAt == updatedAt &&
          listEquals(other.sceneIds, sceneIds));

  @override
  int get hashCode => Object.hash(
    Chapter,
    id,
    volumeId,
    title,
    synopsis,
    status,
    order,
    targetWordCount,
    createdAt,
    updatedAt,
    Object.hashAll(sceneIds),
  );

  @override
  String toString() => 'Chapter($id, $title)';
}
