/// Strongly typed identifiers for the Limpid domain model.
///
/// Each entity kind gets its own [IdTag] so that an [Id] of one kind can never
/// be passed where another kind is expected, while value semantics (equality,
/// hashing) stay shared in a single implementation.
library;

/// Marker interface used to discriminate identifier kinds at compile time.
sealed class IdTag {
  const IdTag();
}

/// Identifier of a CRDT document (a scene is the atomic sync unit).
final class DocumentTag extends IdTag {
  const DocumentTag();
}

/// Identifier of a block inside a document.
final class BlockTag extends IdTag {
  const BlockTag();
}

/// Identifier of an author (a user account).
final class AuthorTag extends IdTag {
  const AuthorTag();
}

/// Identifier of a mark (comment anchor, AI note).
final class MarkTag extends IdTag {
  const MarkTag();
}

/// Identifier of a project.
final class ProjectTag extends IdTag {
  const ProjectTag();
}

/// Identifier of a series.
final class SeriesTag extends IdTag {
  const SeriesTag();
}

/// Identifier of a volume.
final class VolumeTag extends IdTag {
  const VolumeTag();
}

/// Identifier of a chapter.
final class ChapterTag extends IdTag {
  const ChapterTag();
}

/// Identifier of a scene.
final class SceneTag extends IdTag {
  const SceneTag();
}

/// Identifier of a comment thread.
final class CommentTag extends IdTag {
  const CommentTag();
}

/// Identifier of a story-bible character.
final class CharacterTag extends IdTag {
  const CharacterTag();
}

/// Identifier of a story-bible place.
final class PlaceTag extends IdTag {
  const PlaceTag();
}

/// Identifier of a plot thread.
final class PlotThreadTag extends IdTag {
  const PlotThreadTag();
}

/// Identifier of a timeline event.
final class TimelineEventTag extends IdTag {
  const TimelineEventTag();
}

/// Identifier of an export job.
final class ExportJobTag extends IdTag {
  const ExportJobTag();
}

/// Identifier of a cover asset.
final class CoverTag extends IdTag {
  const CoverTag();
}

/// A value object wrapping the textual identifier of an entity.
///
/// The phantom [T] tag guarantees type safety across entity kinds.
final class Id<T extends IdTag> {
  /// Creates an identifier from its textual representation.
  const Id(this.value);

  /// The textual representation of the identifier.
  final String value;

  @override
  bool operator ==(Object other) =>
      identical(this, other) || (other is Id<T> && other.value == value);

  @override
  int get hashCode => Object.hash(T, value);

  @override
  String toString() => value;
}

/// Identifier of a CRDT document.
typedef DocumentId = Id<DocumentTag>;

/// Identifier of a block.
typedef BlockId = Id<BlockTag>;

/// Identifier of an author.
typedef AuthorId = Id<AuthorTag>;

/// Identifier of a mark.
typedef MarkId = Id<MarkTag>;

/// Identifier of a project.
typedef ProjectId = Id<ProjectTag>;

/// Identifier of a series.
typedef SeriesId = Id<SeriesTag>;

/// Identifier of a volume.
typedef VolumeId = Id<VolumeTag>;

/// Identifier of a chapter.
typedef ChapterId = Id<ChapterTag>;

/// Identifier of a scene.
typedef SceneId = Id<SceneTag>;

/// Identifier of a comment thread.
typedef CommentId = Id<CommentTag>;

/// Identifier of a story-bible character.
typedef CharacterId = Id<CharacterTag>;

/// Identifier of a story-bible place.
typedef PlaceId = Id<PlaceTag>;

/// Identifier of a plot thread.
typedef PlotThreadId = Id<PlotThreadTag>;

/// Identifier of a timeline event.
typedef TimelineEventId = Id<TimelineEventTag>;

/// Identifier of an export job.
typedef ExportJobId = Id<ExportJobTag>;

/// Identifier of a cover asset.
typedef CoverId = Id<CoverTag>;
