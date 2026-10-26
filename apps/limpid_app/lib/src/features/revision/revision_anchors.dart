import 'package:limpid_app/src/domain/revision_repository.dart';
import 'package:limpid_app/src/features/revision/revision_models.dart';
import 'package:limpid_core/limpid_core.dart';
import 'package:limpid_quill/limpid_quill.dart' show LimpidCommentAnchor;

/// The anchors of the discussions of [threads] that the blocks of [document]
/// carry.
///
/// A comment is anchored on a mark of the CRDT: the **ranges** live in the
/// document, the **discussion** lives in the repository. The two are joined
/// here, and the range of a block is moved to the coordinates of the editor —
/// the editor lays the blocks out one after the other, each of them followed
/// by its newline.
List<RevisionAnchor> revisionAnchorsOf({
  required CrdtDocument document,
  required List<CommentThread> threads,
}) {
  final Map<MarkId, CommentThread> byMark = <MarkId, CommentThread>{
    for (final CommentThread thread in threads) thread.markId: thread,
  };
  final List<RevisionAnchor> anchors = <RevisionAnchor>[];
  int offset = 0;
  for (final Block block in document.blocks) {
    if (block.deleted) {
      continue;
    }
    for (final MapEntry<MarkId, MarkRange> mark in block.marks.entries) {
      final CommentThread? thread = byMark[mark.key];
      if (thread == null) {
        continue;
      }
      anchors.add(
        RevisionAnchor(
          thread: thread,
          markId: mark.key,
          range: mark.value.shift(offset),
          excerpt: textOfRange(block.content.plainText, mark.value),
        ),
      );
    }
    offset += block.content.plainText.length + 1;
  }
  return List<RevisionAnchor>.unmodifiable(anchors);
}

/// The discussions of the panel, built from their anchors.
///
/// The messages of a discussion are ordered from the oldest to the newest,
/// and every message carries the name and the role of its author.
List<RevisionThread> revisionThreadsOf({
  required List<RevisionAnchor> anchors,
  required List<ProjectMember> members,
}) {
  final Map<AuthorId, ProjectMember> byAuthor = <AuthorId, ProjectMember>{
    for (final ProjectMember member in members) member.id: member,
  };
  return List<RevisionThread>.unmodifiable(<RevisionThread>[
    for (final RevisionAnchor anchor in anchors)
      RevisionThread(
        thread: anchor.thread,
        comments: <RevisionComment>[
          for (final Comment comment in anchor.thread.comments)
            RevisionComment(
              comment: comment,
              authorName: _authorNameOf(comment, byAuthor),
              role: byAuthor[comment.author]?.role,
            ),
        ],
        anchor: anchor,
      ),
  ]);
}

/// The anchors the editor of the manuscript understands.
///
/// The editor decorates the ranges of the anchors with the style of the
/// design system; the panel drives the selection through the identifier of
/// the anchor.
List<LimpidCommentAnchor> editorAnchorsOf(List<RevisionThread> threads) {
  return List<LimpidCommentAnchor>.unmodifiable(<LimpidCommentAnchor>[
    for (final RevisionThread thread in threads)
      if (thread.anchor case final RevisionAnchor anchor)
        LimpidCommentAnchor(
          id: anchor.markId.value,
          range: anchor.range,
          body: thread.first?.comment.body ?? '',
          authorName: thread.first?.authorName,
          isResolved: thread.isResolved,
        ),
  ]);
}

/// The text covered by [range] in [text].
///
/// A range that reaches past the end of the text is truncated: the text may
/// have been rewritten since the comment was written.
String textOfRange(String text, MarkRange range) {
  if (range.start >= text.length) {
    return '';
  }
  final int end = range.end > text.length ? text.length : range.end;
  return text.substring(range.start, end);
}

/// The name the panel shows for the author of [comment].
String _authorNameOf(Comment comment, Map<AuthorId, ProjectMember> members) {
  final ProjectMember? member = members[comment.author];
  if (member != null) {
    return member.displayName;
  }
  return comment.author.value;
}
