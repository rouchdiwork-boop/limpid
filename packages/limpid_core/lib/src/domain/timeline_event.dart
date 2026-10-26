import 'package:limpid_core/src/internal/collections.dart';

import 'ids.dart';

/// A point of the story timeline (O4).
final class TimelineEvent {
  /// Creates a timeline event.
  const TimelineEvent({
    required this.id,
    required this.title,
    this.description = '',
    this.storyTime = '',
    this.narrativePosition = 0,
    this.chapterIds = const <ChapterId>[],
    this.characterIds = const <CharacterId>[],
    this.placeIds = const <PlaceId>[],
    this.isKeyMoment = false,
    this.createdAt,
    this.updatedAt,
  });

  /// Identifier of the event.
  final TimelineEventId id;

  /// Title of the event.
  final String title;

  /// Description of the event.
  final String description;

  /// In-world date or duration of the event, free-form.
  final String storyTime;

  /// Position of the event in the narrative order.
  final int narrativePosition;

  /// Chapters in which the event happens.
  final List<ChapterId> chapterIds;

  /// Characters involved in the event.
  final List<CharacterId> characterIds;

  /// Places involved in the event.
  final List<PlaceId> placeIds;

  /// Whether this event is a turning point.
  final bool isKeyMoment;

  /// Creation timestamp.
  final DateTime? createdAt;

  /// Last modification timestamp.
  final DateTime? updatedAt;

  /// Returns a copy of this event with the given fields replaced.
  TimelineEvent copyWith({
    String? title,
    String? description,
    String? storyTime,
    int? narrativePosition,
    List<ChapterId>? chapterIds,
    List<CharacterId>? characterIds,
    List<PlaceId>? placeIds,
    bool? isKeyMoment,
    DateTime? updatedAt,
  }) {
    return TimelineEvent(
      id: id,
      title: title ?? this.title,
      description: description ?? this.description,
      storyTime: storyTime ?? this.storyTime,
      narrativePosition: narrativePosition ?? this.narrativePosition,
      chapterIds: chapterIds ?? this.chapterIds,
      characterIds: characterIds ?? this.characterIds,
      placeIds: placeIds ?? this.placeIds,
      isKeyMoment: isKeyMoment ?? this.isKeyMoment,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is TimelineEvent &&
          other.id == id &&
          other.title == title &&
          other.description == description &&
          other.storyTime == storyTime &&
          other.narrativePosition == narrativePosition &&
          other.isKeyMoment == isKeyMoment &&
          other.createdAt == createdAt &&
          other.updatedAt == updatedAt &&
          listEquals(other.chapterIds, chapterIds) &&
          listEquals(other.characterIds, characterIds) &&
          listEquals(other.placeIds, placeIds));

  @override
  int get hashCode => Object.hash(
    TimelineEvent,
    id,
    title,
    description,
    storyTime,
    narrativePosition,
    isKeyMoment,
    createdAt,
    updatedAt,
    Object.hashAll(chapterIds),
    Object.hashAll(characterIds),
    Object.hashAll(placeIds),
  );

  @override
  String toString() => 'TimelineEvent($id, $title)';
}
