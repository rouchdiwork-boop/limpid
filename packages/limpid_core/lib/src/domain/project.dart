import 'package:limpid_core/src/internal/collections.dart';
import 'package:limpid_core/src/sync/order_key.dart';

import 'enums.dart';
import 'ids.dart';

/// The root container of the manuscript tree.
///
/// A project owns an ordered list of series. A project may also hold
/// chapters directly when the author does not use the series / volume
/// levels (D-02).
final class Project {
  /// Creates a project.
  const Project({
    required this.id,
    required this.ownerId,
    required this.title,
    required this.order,
    this.synopsis = '',
    this.status = ManuscriptStatus.draft,
    this.isPublic = false,
    this.seriesIds = const <SeriesId>[],
    this.chapterIds = const <ChapterId>[],
    this.createdAt,
    this.updatedAt,
  });

  /// Identifier of the project.
  final ProjectId id;

  /// Account owning the project.
  final AuthorId ownerId;

  /// Title of the project.
  final String title;

  /// Short synopsis of the project.
  final String synopsis;

  /// Editorial pipeline stage of the project.
  final ManuscriptStatus status;

  /// Whether the project is in the showcase of the application.
  ///
  /// The visibility is a **second state**, not a synonym of [status] (D-33):
  /// a book can be published — the manuscript is finished — without being in
  /// the showcase. The action of publication writes both states at once.
  final bool isPublic;

  /// Fractional index of the project in the library.
  final OrderKey order;

  /// Ordered identifiers of the series of this project.
  final List<SeriesId> seriesIds;

  /// Ordered identifiers of the chapters directly attached to this project.
  final List<ChapterId> chapterIds;

  /// Creation timestamp.
  final DateTime? createdAt;

  /// Last modification timestamp.
  final DateTime? updatedAt;

  /// Returns a copy of this project with the given fields replaced.
  Project copyWith({
    String? title,
    String? synopsis,
    ManuscriptStatus? status,
    bool? isPublic,
    OrderKey? order,
    List<SeriesId>? seriesIds,
    List<ChapterId>? chapterIds,
    DateTime? updatedAt,
  }) {
    return Project(
      id: id,
      ownerId: ownerId,
      title: title ?? this.title,
      synopsis: synopsis ?? this.synopsis,
      status: status ?? this.status,
      isPublic: isPublic ?? this.isPublic,
      order: order ?? this.order,
      seriesIds: seriesIds ?? this.seriesIds,
      chapterIds: chapterIds ?? this.chapterIds,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Project &&
          other.id == id &&
          other.ownerId == ownerId &&
          other.title == title &&
          other.synopsis == synopsis &&
          other.status == status &&
          other.isPublic == isPublic &&
          other.order == order &&
          other.createdAt == createdAt &&
          other.updatedAt == updatedAt &&
          listEquals(other.seriesIds, seriesIds) &&
          listEquals(other.chapterIds, chapterIds));

  @override
  int get hashCode => Object.hash(
    Project,
    id,
    ownerId,
    title,
    synopsis,
    status,
    isPublic,
    order,
    createdAt,
    updatedAt,
    Object.hashAll(seriesIds),
    Object.hashAll(chapterIds),
  );

  @override
  String toString() => 'Project($id, $title)';
}
