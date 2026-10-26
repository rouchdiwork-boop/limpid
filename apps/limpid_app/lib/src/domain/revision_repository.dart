import 'package:flutter/foundation.dart';
import 'package:limpid_core/limpid_core.dart';

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
  Future<List<CommentThread>> loadThreads(String projectId);

  /// Writes a discussion of a project.
  ///
  /// Writing the same discussion twice is a no-op: the discussions are keyed
  /// by their identifier.
  Future<void> saveThread(String projectId, CommentThread thread);

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
    Map<String, List<CommentThread>> threads =
        const <String, List<CommentThread>>{},
    Map<String, List<ProjectMember>> members =
        const <String, List<ProjectMember>>{},
    Map<String, CrdtDocument> documents = const <String, CrdtDocument>{},
  }) : _threads = <String, List<CommentThread>>{
         for (final MapEntry<String, List<CommentThread>> entry
             in threads.entries)
           entry.key: List<CommentThread>.of(entry.value),
       },
       _members = <String, List<ProjectMember>>{
         for (final MapEntry<String, List<ProjectMember>> entry
             in members.entries)
           entry.key: List<ProjectMember>.of(entry.value),
       },
       _documents = Map<String, CrdtDocument>.of(documents);

  final Map<String, List<CommentThread>> _threads;
  final Map<String, List<ProjectMember>> _members;
  final Map<String, CrdtDocument> _documents;

  @override
  Future<List<CommentThread>> loadThreads(String projectId) async {
    return List<CommentThread>.unmodifiable(
      _threads[projectId] ?? const <CommentThread>[],
    );
  }

  @override
  Future<void> saveThread(String projectId, CommentThread thread) async {
    final List<CommentThread> threads = _threads.putIfAbsent(
      projectId,
      () => <CommentThread>[],
    );
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
