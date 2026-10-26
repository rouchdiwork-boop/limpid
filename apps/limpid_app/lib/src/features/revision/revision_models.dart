import 'package:flutter/foundation.dart';
import 'package:limpid_app/l10n/generated/app_localizations.dart';
import 'package:limpid_core/limpid_core.dart';

/// The anchor of a discussion in the manuscript.
///
/// The range is expressed in the coordinates of the editor document, not of
/// the block: the editor decorates the text with it.
@immutable
class RevisionAnchor {
  /// Creates an anchor.
  const RevisionAnchor({
    required this.thread,
    required this.markId,
    required this.range,
    required this.excerpt,
  });

  /// The discussion the anchor belongs to.
  final CommentThread thread;

  /// The mark of the CRDT carrying the anchor.
  final MarkId markId;

  /// The range covered by the anchor, in the coordinates of the document.
  final MarkRange range;

  /// The text covered by the anchor.
  final String excerpt;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is RevisionAnchor &&
          other.thread == thread &&
          other.markId == markId &&
          other.range == range &&
          other.excerpt == excerpt);

  @override
  int get hashCode => Object.hash(thread, markId, range, excerpt);

  @override
  String toString() => 'RevisionAnchor($markId, $range)';
}

/// A message of a discussion, with the author the panel shows.
@immutable
class RevisionComment {
  /// Creates a message.
  const RevisionComment({
    required this.comment,
    required this.authorName,
    this.role,
  });

  /// The message of the domain.
  final Comment comment;

  /// The name of the author, as the panel shows it.
  final String authorName;

  /// The role of the author, `null` when they are not a collaborator.
  final ProjectRole? role;

  /// Whether the author of the message holds the role of the project owner.
  bool get isOwner => role == ProjectRole.owner;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is RevisionComment &&
          other.comment == comment &&
          other.authorName == authorName &&
          other.role == role);

  @override
  int get hashCode => Object.hash(comment, authorName, role);

  @override
  String toString() => 'RevisionComment(${comment.id}, $authorName)';
}

/// A discussion of the manuscript, as the panel shows it.
@immutable
class RevisionThread {
  /// Creates a discussion.
  const RevisionThread({
    required this.thread,
    required this.comments,
    this.anchor,
  });

  /// The discussion of the domain.
  final CommentThread thread;

  /// The messages of the discussion, oldest first.
  final List<RevisionComment> comments;

  /// The anchor of the discussion in the manuscript, `null` when the
  /// discussion is not anchored in the scene being read.
  final RevisionAnchor? anchor;

  /// The identifier of the discussion.
  CommentId get id => thread.id;

  /// Whether the discussion is closed.
  bool get isResolved => thread.isResolved;

  /// The first message of the discussion, `null` when it holds none.
  RevisionComment? get first => comments.isEmpty ? null : comments.first;

  /// The replies of the discussion, oldest first.
  List<RevisionComment> get replies =>
      comments.length <= 1 ? const <RevisionComment>[] : comments.sublist(1);

  /// Returns a copy of this discussion with the given fields replaced.
  RevisionThread copyWith({
    List<RevisionComment>? comments,
    RevisionAnchor? anchor,
  }) {
    return RevisionThread(
      thread: thread,
      comments: comments ?? this.comments,
      anchor: anchor ?? this.anchor,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is RevisionThread &&
          other.thread == thread &&
          other.anchor == anchor &&
          listEquals(other.comments, comments));

  @override
  int get hashCode => Object.hash(thread, anchor, Object.hashAll(comments));

  @override
  String toString() => 'RevisionThread(${thread.id}, ${comments.length})';
}

/// The label the panel shows for a role.
///
/// The roles of the collaborators have their own vocabulary: they are the
/// names the author gives to the people around the manuscript.
String roleLabelOf(AppLocalizations strings, ProjectRole role) {
  return switch (role) {
    ProjectRole.owner => strings.revisionRoleOwner,
    ProjectRole.coAuthor => strings.revisionRoleCoAuthor,
    ProjectRole.betaReader => strings.revisionRoleBetaReader,
    ProjectRole.reader => strings.revisionRoleReader,
  };
}
