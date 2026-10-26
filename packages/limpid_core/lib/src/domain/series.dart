import 'package:limpid_core/src/internal/collections.dart';
import 'package:limpid_core/src/sync/order_key.dart';

import 'ids.dart';

/// An optional grouping of projects under a common universe or saga.
final class Series {
  /// Creates a series.
  const Series({
    required this.id,
    required this.projectId,
    required this.title,
    required this.order,
    this.synopsis = '',
    this.volumeIds = const <VolumeId>[],
    this.createdAt,
    this.updatedAt,
  });

  /// Identifier of the series.
  final SeriesId id;

  /// Project this series belongs to.
  final ProjectId projectId;

  /// Title of the series.
  final String title;

  /// Short synopsis of the series.
  final String synopsis;

  /// Fractional index of the series inside its project.
  final OrderKey order;

  /// Ordered identifiers of the volumes of this series.
  final List<VolumeId> volumeIds;

  /// Creation timestamp.
  final DateTime? createdAt;

  /// Last modification timestamp.
  final DateTime? updatedAt;

  /// Returns a copy of this series with the given fields replaced.
  Series copyWith({
    String? title,
    String? synopsis,
    OrderKey? order,
    List<VolumeId>? volumeIds,
    DateTime? updatedAt,
  }) {
    return Series(
      id: id,
      projectId: projectId,
      title: title ?? this.title,
      synopsis: synopsis ?? this.synopsis,
      order: order ?? this.order,
      volumeIds: volumeIds ?? this.volumeIds,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Series &&
          other.id == id &&
          other.projectId == projectId &&
          other.title == title &&
          other.synopsis == synopsis &&
          other.order == order &&
          other.createdAt == createdAt &&
          other.updatedAt == updatedAt &&
          listEquals(other.volumeIds, volumeIds));

  @override
  int get hashCode => Object.hash(
    Series,
    id,
    projectId,
    title,
    synopsis,
    order,
    createdAt,
    updatedAt,
    Object.hashAll(volumeIds),
  );

  @override
  String toString() => 'Series($id, $title)';
}
