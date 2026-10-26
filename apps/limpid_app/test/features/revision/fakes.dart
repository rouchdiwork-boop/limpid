import 'package:limpid_app/src/domain/revision_repository.dart';
import 'package:limpid_app/src/features/revision/revision_models.dart';
import 'package:limpid_core/limpid_core.dart';

/// The identifier of the project used by the tests.
const String kRevisionProjectId = 'projet-1';

/// The account of the author of the book used by the tests.
const AuthorId kRevisionAuthor = AuthorId('auteur-1');

/// A repository of discussions driven by the test.
///
/// The fake records the discussions the panel writes, so that a test can
/// assert that the resolution of a thread reaches the storage. It also
/// serves the history of the documents it holds.
final class FakeRevisionRepository implements RevisionRepository {
  /// Creates the fake.
  FakeRevisionRepository({
    List<CommentThread> threads = const <CommentThread>[],
    List<ProjectMember> members = const <ProjectMember>[],
    Map<String, CrdtDocument> documents = const <String, CrdtDocument>{},
  }) : threads = List<CommentThread>.of(threads),
       members = List<ProjectMember>.of(members),
       documents = Map<String, CrdtDocument>.of(documents);

  /// The discussions of the project.
  final List<CommentThread> threads;

  /// The excerpts the discussions carry, by their identifier.
  final Map<String, String> excerpts = <String, String>{};

  /// The collaborators of the project.
  final List<ProjectMember> members;

  /// The documents whose history the fake serves.
  final Map<String, CrdtDocument> documents;

  /// The discussions the panel wrote.
  final List<CommentThread> saved = <CommentThread>[];

  @override
  Future<List<StoredThread>> loadThreads(String projectId) async {
    return List<StoredThread>.unmodifiable(<StoredThread>[
      for (final CommentThread thread in threads)
        StoredThread(thread: thread, excerpt: excerpts[thread.id.value] ?? ''),
    ]);
  }

  @override
  Future<void> saveThread(
    String projectId,
    CommentThread thread, {
    String excerpt = '',
  }) async {
    saved.add(thread);
    if (excerpt.isNotEmpty) {
      excerpts[thread.id.value] = excerpt;
    }
    final int index = threads.indexWhere(
      (CommentThread current) => current.id == thread.id,
    );
    if (index < 0) {
      threads.add(thread);
      return;
    }
    threads[index] = thread;
  }

  @override
  Future<List<ProjectMember>> loadMembers(String projectId) async {
    return List<ProjectMember>.unmodifiable(members);
  }

  @override
  Future<List<DocumentRevision>> loadRevisions(String documentId) async {
    final CrdtDocument? document = documents[documentId];
    if (document == null) return const <DocumentRevision>[];
    return List<DocumentRevision>.unmodifiable(revisionsOf(document));
  }

  @override
  Future<RevisionComparison> compareRevisions(
    String documentId, {
    required VersionRef from,
    required VersionRef to,
  }) async {
    final CrdtDocument? document = documents[documentId];
    if (document == null) return RevisionComparison.empty(from, to);
    return compareDocumentRevisions(document, from: from, to: to);
  }
}

/// Builds a message of a discussion.
Comment fakeComment({
  required String id,
  required String threadId,
  required String authorId,
  required String body,
  DateTime? createdAt,
}) {
  return Comment(
    id: CommentId(id),
    threadId: CommentId(threadId),
    author: AuthorId(authorId),
    body: body,
    createdAt: createdAt ?? DateTime(2026, 10, 20),
  );
}

/// Builds a discussion.
CommentThread fakeThread({
  required String id,
  required String markId,
  List<Comment> comments = const <Comment>[],
  bool isResolved = false,
}) {
  return CommentThread(
    id: CommentId(id),
    markId: MarkId(markId),
    comments: List<Comment>.unmodifiable(comments),
    isResolved: isResolved,
  );
}

/// Builds a collaborator of the project.
ProjectMember fakeMember({
  required String id,
  required String displayName,
  required ProjectRole role,
}) {
  return ProjectMember(id: AuthorId(id), displayName: displayName, role: role);
}

/// Builds a message, as the panel shows it.
RevisionComment fakeRevisionComment({
  required Comment comment,
  required String authorName,
  ProjectRole? role,
}) {
  return RevisionComment(comment: comment, authorName: authorName, role: role);
}

/// Builds a discussion, as the panel shows it.
RevisionThread fakeRevisionThread({
  required CommentThread thread,
  List<RevisionComment> comments = const <RevisionComment>[],
  RevisionAnchor? anchor,
}) {
  return RevisionThread(
    thread: thread,
    comments: comments.isEmpty
        ? <RevisionComment>[
            for (final Comment comment in thread.comments)
              fakeRevisionComment(
                comment: comment,
                authorName: comment.author.value,
              ),
          ]
        : comments,
    anchor: anchor,
  );
}

/// Builds an anchor of a discussion.
RevisionAnchor fakeAnchor({
  required CommentThread thread,
  required String markId,
  int start = 0,
  int end = 12,
  String excerpt = 'Le sel qui vie',
}) {
  return RevisionAnchor(
    thread: thread,
    markId: MarkId(markId),
    range: MarkRange(start: start, end: end),
    excerpt: excerpt,
  );
}
