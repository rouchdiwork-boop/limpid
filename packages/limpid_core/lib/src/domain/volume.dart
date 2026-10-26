import 'package:limpid_core/src/internal/collections.dart';
import 'package:limpid_core/src/sync/order_key.dart';

import 'ids.dart';

/// A subdivision of a series grouping several chapters.
final class Volume {
  /// Creates a volume.
  const Volume({
    required this.id,
    required this.seriesId,
    required this.title,
    required this.order,
    this.synopsis = '',
    this.chapterIds = const <ChapterId>[],
    this.createdAt,
    this.updatedAt,
  });

  /// Identifier of the volume.
  final VolumeId id;

  /// Series this volume belongs to.
  final SeriesId seriesId;

  /// Title of the volume.
  final String title;

  /// Short synopsis of the volume.
  final String synopsis;

  /// Fractional index of the volume inside its series.
  final OrderKey order;

  /// Ordered identifiers of the chapters of this volume.
  final List<ChapterId> chapterIds;

  /// Creation timestamp.
  final DateTime? createdAt;

  /// Last modification timestamp.
  final DateTime? updatedAt;

  /// Returns a copy of this volume with the given fields replaced.
  Volume copyWith({
    String? title,
    String? synopsis,
    OrderKey? order,
    List<ChapterId>? chapterIds,
    DateTime? updatedAt,
  }) {
    return Volume(
      id: id,
      seriesId: seriesId,
      title: title ?? this.title,
      synopsis: synopsis ?? this.synopsis,
      order: order ?? this.order,
      chapterIds: chapterIds ?? this.chapterIds,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Volume &&
          other.id == id &&
          other.seriesId == seriesId &&
          other.title == title &&
          other.synopsis == synopsis &&
          other.order == order &&
          other.createdAt == createdAt &&
          other.updatedAt == updatedAt &&
          listEquals(other.chapterIds, chapterIds));

  @override
  int get hashCode => Object.hash(
    Volume,
    id,
    seriesId,
    title,
    synopsis,
    order,
    createdAt,
    updatedAt,
    Object.hashAll(chapterIds),
  );

  @override
  String toString() => 'Volume($id, $title)';
}
