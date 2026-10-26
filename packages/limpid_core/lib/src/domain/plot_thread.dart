import 'ids.dart';

/// The lifecycle of a plot thread.
enum PlotThreadStatus {
  /// Planned but not started.
  planned,

  /// Under development.
  active,

  /// Temporarily paused.
  paused,

  /// Concluded.
  resolved,

  /// Dropped from the manuscript.
  dropped,
}

/// A narrative line of the manuscript (O5).
final class PlotThread {
  /// Creates a plot thread.
  const PlotThread({
    required this.id,
    required this.title,
    this.status = PlotThreadStatus.planned,
    this.description = '',
    this.resolution = '',
    this.characterIds = const <CharacterId>[],
    this.chapterIds = const <ChapterId>[],
    this.startOrder = 0,
    this.endOrder,
    this.createdAt,
    this.updatedAt,
  });

  /// Identifier of the thread.
  final PlotThreadId id;

  /// Title of the thread.
  final String title;

  /// Lifecycle stage of the thread.
  final PlotThreadStatus status;

  /// Description of the thread.
  final String description;

  /// How the thread is resolved, when it is.
  final String resolution;

  /// Identifiers of the characters involved in this thread.
  final List<CharacterId> characterIds;

  /// Identifiers of the chapters carrying this thread.
  final List<ChapterId> chapterIds;

  /// Ordinal position of the beginning of the thread.
  final int startOrder;

  /// Ordinal position of the end of the thread, `null` while open.
  final int? endOrder;

  /// Creation timestamp.
  final DateTime? createdAt;

  /// Last modification timestamp.
  final DateTime? updatedAt;

  /// Whether the thread is concluded.
  bool get isResolved => status == PlotThreadStatus.resolved;

  /// Returns a copy of this thread with the given fields replaced.
  PlotThread copyWith({
    String? title,
    PlotThreadStatus? status,
    String? description,
    String? resolution,
    List<CharacterId>? characterIds,
    List<ChapterId>? chapterIds,
    int? startOrder,
    int? endOrder,
    DateTime? updatedAt,
  }) {
    return PlotThread(
      id: id,
      title: title ?? this.title,
      status: status ?? this.status,
      description: description ?? this.description,
      resolution: resolution ?? this.resolution,
      characterIds: characterIds ?? this.characterIds,
      chapterIds: chapterIds ?? this.chapterIds,
      startOrder: startOrder ?? this.startOrder,
      endOrder: endOrder ?? this.endOrder,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is PlotThread &&
          other.id == id &&
          other.title == title &&
          other.status == status &&
          other.description == description &&
          other.resolution == resolution &&
          other.startOrder == startOrder &&
          other.endOrder == endOrder &&
          other.createdAt == createdAt &&
          other.updatedAt == updatedAt);

  @override
  int get hashCode => Object.hash(
    PlotThread,
    id,
    title,
    status,
    description,
    resolution,
    startOrder,
    endOrder,
    createdAt,
    updatedAt,
  );

  @override
  String toString() => 'PlotThread($id, $title, $status)';
}
