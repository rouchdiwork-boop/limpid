import 'package:flutter/foundation.dart';
import 'package:limpid_core/limpid_core.dart';

/// The maximum length of the excerpt carried by a discussion.
///
/// The server keeps the same bound (see `maxCommentExcerptLength` of the
/// API) : an excerpt longer than that would be refused by the API.
const int maxRevisionExcerptLength = 1000;

/// A discussion and the excerpt it carries.
///
/// The domain of `limpid_core` describes the discussion itself
/// ([CommentThread]), but not the words it comments: the contract of the
/// review carries them.
@immutable
class StoredThread {
  /// Creates a stored discussion.
  const StoredThread({required this.thread, this.excerpt = ''});

  /// The discussion of the domain.
  final CommentThread thread;

  /// The words the author commented.
  final String excerpt;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is StoredThread &&
          other.thread == thread &&
          other.excerpt == excerpt);

  @override
  int get hashCode => Object.hash(thread, excerpt);

  @override
  String toString() => 'StoredThread(${thread.id}, ${excerpt.length} chars)';
}

/// A collaborator of a project and the role it holds inside it.
///
/// The domain of `limpid_core` describes the roles ([ProjectRole]) and the
/// discussions ([CommentThread]), but not the people who hold them: the
/// contract of the review carries them.
@immutable
class ProjectMember {
  /// Creates a collaborator.
  const ProjectMember({
    required this.id,
    required this.displayName,
    required this.role,
  });

  /// The account of the collaborator.
  final AuthorId id;

  /// The name the interface shows.
  final String displayName;

  /// The role the collaborator holds in the project.
  final ProjectRole role;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ProjectMember &&
          other.id == id &&
          other.displayName == displayName &&
          other.role == role);

  @override
  int get hashCode => Object.hash(id, displayName, role);

  @override
  String toString() => 'ProjectMember($id, $role)';
}

/// The storage of the discussions anchored on the manuscripts.
///
/// The CRDT of `limpid_core` stores the **anchors** of the comments — they
/// are marks added to the document, and they never conflict with the text —
/// but not the discussion itself, nor its author, nor its resolution. The
/// contract below therefore carries the conversation and the collaborators
/// who hold it, and the composition root of the application overrides
/// [revisionRepositoryProvider] with the durable implementation.
///
/// The two halves meet in `features/revision/revision_anchors.dart`: the
/// ranges come from the document, the discussion comes from here.
///
/// ## The history of the versions
///
/// The contract also carries the **history** of a document: the list of its
/// revisions, and the comparison of two of them. The comparison is made
/// block by block, on the states of the blocks — never on two texts.
abstract interface class RevisionRepository {
  /// The discussions of a project, oldest first.
  ///
  /// Every discussion carries the excerpt it holds: the words the author
  /// commented when the discussion was created.
  Future<List<StoredThread>> loadThreads(String projectId);

  /// Writes a discussion of a project.
  ///
  /// The excerpt holds the words the author commented. Writing the same
  /// discussion twice is a no-op: the discussions are keyed by their
  /// identifier.
  Future<void> saveThread(
    String projectId,
    CommentThread thread, {
    String excerpt = '',
  });

  /// The collaborators of a project, with the role they hold.
  Future<List<ProjectMember>> loadMembers(String projectId);

  /// The revisions of a document, the oldest first.
  ///
  /// The revisions are the operations the document holds: every version of
  /// every block is a point of the history.
  Future<List<DocumentRevision>> loadRevisions(String documentId);

  /// Compares two revisions of a document, block by block.
  ///
  /// The comparison says which blocks changed, and how: they were added,
  /// they were removed, their content changed or they moved.
  Future<RevisionComparison> compareRevisions(
    String documentId, {
    required VersionRef from,
    required VersionRef to,
  });
}

/// A repository keeping the discussions in the memory of the process.
///
/// It is the default implementation: the review stays usable before the
/// durable storage is wired, and the tests override the provider with their
/// own fake.
final class InMemoryRevisionRepository implements RevisionRepository {
  /// Creates the repository.
  InMemoryRevisionRepository({
    Map<String, List<StoredThread>> threads =
        const <String, List<StoredThread>>{},
    Map<String, List<ProjectMember>> members =
        const <String, List<ProjectMember>>{},
    Map<String, CrdtDocument> documents = const <String, CrdtDocument>{},
  }) : _threads = <String, List<StoredThread>>{
         for (final MapEntry<String, List<StoredThread>> entry
             in threads.entries)
           entry.key: List<StoredThread>.of(entry.value),
       },
       _members = <String, List<ProjectMember>>{
         for (final MapEntry<String, List<ProjectMember>> entry
             in members.entries)
           entry.key: List<ProjectMember>.of(entry.value),
       },
       _documents = Map<String, CrdtDocument>.of(documents);

  final Map<String, List<StoredThread>> _threads;
  final Map<String, List<ProjectMember>> _members;
  final Map<String, CrdtDocument> _documents;

  @override
  Future<List<StoredThread>> loadThreads(String projectId) async {
    return List<StoredThread>.unmodifiable(
      _threads[projectId] ?? const <StoredThread>[],
    );
  }

  @override
  Future<void> saveThread(
    String projectId,
    CommentThread thread, {
    String excerpt = '',
  }) async {
    final List<StoredThread> threads = _threads.putIfAbsent(
      projectId,
      () => <StoredThread>[],
    );
    final int index = threads.indexWhere(
      (StoredThread current) => current.thread.id == thread.id,
    );
    if (index < 0) {
      threads.add(StoredThread(thread: thread, excerpt: excerpt));
      return;
    }
    threads[index] = StoredThread(
      thread: thread,
      excerpt: excerpt.isEmpty ? threads[index].excerpt : excerpt,
    );
  }

  @override
  Future<List<ProjectMember>> loadMembers(String projectId) async {
    return List<ProjectMember>.unmodifiable(
      _members[projectId] ?? const <ProjectMember>[],
    );
  }

  @override
  Future<List<DocumentRevision>> loadRevisions(String documentId) async {
    final CrdtDocument? document = _documents[documentId];
    if (document == null) return const <DocumentRevision>[];
    return List<DocumentRevision>.unmodifiable(revisionsOf(document));
  }

  @override
  Future<RevisionComparison> compareRevisions(
    String documentId, {
    required VersionRef from,
    required VersionRef to,
  }) async {
    final CrdtDocument? document = _documents[documentId];
    if (document == null) return RevisionComparison.empty(from, to);
    return compareDocumentRevisions(document, from: from, to: to);
  }
}
