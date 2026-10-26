import 'package:limpid_core/src/internal/collections.dart';

import 'ids.dart';

/// A single message inside a comment thread.
final class Comment {
  /// Creates a comment.
  const Comment({
    required this.id,
    required this.threadId,
    required this.author,
    required this.body,
    required this.createdAt,
    this.editedAt,
  });

  /// Identifier of the comment.
  final CommentId id;

  /// Identifier of the thread this comment belongs to.
  final CommentId threadId;

  /// Author of the comment.
  final AuthorId author;

  /// Body of the comment.
  final String body;

  /// Creation timestamp.
  final DateTime createdAt;

  /// Last edit timestamp, `null` when never edited.
  final DateTime? editedAt;

  /// Whether the comment was edited after creation.
  bool get isEdited => editedAt != null;

  /// Returns a copy of this comment with the given fields replaced.
  Comment copyWith({String? body, DateTime? editedAt}) {
    return Comment(
      id: id,
      threadId: threadId,
      author: author,
      body: body ?? this.body,
      createdAt: createdAt,
      editedAt: editedAt ?? this.editedAt,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Comment &&
          other.id == id &&
          other.threadId == threadId &&
          other.author == author &&
          other.body == body &&
          other.createdAt == createdAt &&
          other.editedAt == editedAt);

  @override
  int get hashCode =>
      Object.hash(Comment, id, threadId, author, body, createdAt, editedAt);

  @override
  String toString() => 'Comment($id)';
}

/// The marker of the fields a copy leaves untouched.
const Object _untouched = Object();

/// A conversation anchored on a mark (a comment mark).
final class CommentThread {
  /// Creates a comment thread.
  const CommentThread({
    required this.id,
    required this.markId,
    required this.comments,
    this.isResolved = false,
    this.resolvedAt,
  });

  /// Identifier of the thread.
  final CommentId id;

  /// Mark this thread is anchored to.
  final MarkId markId;

  /// Messages of the thread, ordered from oldest to newest.
  final List<Comment> comments;

  /// Whether the thread has been resolved.
  final bool isResolved;

  /// Timestamp of the resolution, `null` when unresolved.
  final DateTime? resolvedAt;

  /// Number of messages in this thread.
  int get messageCount => comments.length;

  /// Returns a copy of this thread with the given fields replaced.
  ///
  /// The resolution is cleared when [resolvedAt] is `null`: a reopened thread
  /// keeps no date. [resolve] and [reopen] are the two coherent transitions
  /// of a thread.
  CommentThread copyWith({
    List<Comment>? comments,
    bool? isResolved,
    Object? resolvedAt = _untouched,
  }) {
    return CommentThread(
      id: id,
      markId: markId,
      comments: comments ?? this.comments,
      isResolved: isResolved ?? this.isResolved,
      resolvedAt: identical(resolvedAt, _untouched)
          ? this.resolvedAt
          : resolvedAt as DateTime?,
    );
  }

  /// Returns a copy of this thread, resolved at [date].
  ///
  /// The date of the resolution is kept by the copy: the thread it is built
  /// from stays untouched.
  CommentThread resolve(DateTime date) {
    return CommentThread(
      id: id,
      markId: markId,
      comments: comments,
      isResolved: true,
      resolvedAt: date,
    );
  }

  /// Returns a copy of this thread, opened again.
  ///
  /// The reopened thread keeps no date of resolution.
  CommentThread reopen() {
    return CommentThread(
      id: id,
      markId: markId,
      comments: comments,
      isResolved: false,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is CommentThread &&
          other.id == id &&
          other.markId == markId &&
          other.isResolved == isResolved &&
          other.resolvedAt == resolvedAt &&
          listEquals(other.comments, comments));

  @override
  int get hashCode => Object.hash(
    CommentThread,
    id,
    markId,
    isResolved,
    resolvedAt,
    Object.hashAll(comments),
  );

  @override
  String toString() => 'CommentThread($id, ${comments.length} messages)';
}
