import 'package:limpid_app/src/data/account_snapshot_store.dart';
import 'package:limpid_app/src/data/app_database.dart';
import 'package:limpid_app/src/data/revision_store.dart';
import 'package:limpid_app/src/domain/revision_repository.dart';
import 'package:limpid_core/limpid_core.dart';
import 'package:limpid_sync/limpid_sync.dart';

/// The discussions of the projects, served by the local database.
///
/// The repository is the durable implementation of the contract of the
/// review: the discussions are written in the SQLite file of the device and
/// read back from it, so they survive the restart of the application.
///
/// The **anchors** are not stored here: they are marks of the CRDT, and the
/// document carries them. The repository only holds the conversation itself.
///
/// ## The history of the versions
///
/// The history comes from the CRDT document itself: the forest of the
/// versions of the blocks is the history of the manuscript. The repository
/// reads the snapshot of the document — the compacted state and the journal
/// that the synchronisation maintains — and compares two of its revisions
/// with the comparator of `limpid_core`.
final class LocalRevisionRepository implements RevisionRepository {
  /// Creates a repository on top of [database].
  LocalRevisionRepository({required AppDatabase database})
    : _store = RevisionStore(database.sync),
      _snapshots = database.snapshotsFor(() => database.account.accountId);

  final RevisionStore _store;
  final AccountSnapshotStore _snapshots;

  @override
  Future<List<CommentThread>> loadThreads(String projectId) =>
      _store.listThreads(projectId);

  @override
  Future<void> saveThread(String projectId, CommentThread thread) =>
      _store.saveThread(projectId, thread);

  @override
  Future<List<ProjectMember>> loadMembers(String projectId) async {
    final String? owner = await _store.findProjectOwner(projectId);
    if (owner == null) return const <ProjectMember>[];
    return List<ProjectMember>.unmodifiable(<ProjectMember>[
      ProjectMember(
        id: AuthorId(owner),
        displayName: owner,
        role: ProjectRole.owner,
      ),
    ]);
  }

  @override
  Future<List<DocumentRevision>> loadRevisions(String documentId) async {
    final CrdtDocument? document = await _documentOf(documentId);
    if (document == null) return const <DocumentRevision>[];
    return List<DocumentRevision>.unmodifiable(revisionsOf(document));
  }

  @override
  Future<RevisionComparison> compareRevisions(
    String documentId, {
    required VersionRef from,
    required VersionRef to,
  }) async {
    final CrdtDocument? document = await _documentOf(documentId);
    if (document == null) return RevisionComparison.empty(from, to);
    return compareDocumentRevisions(document, from: from, to: to);
  }

  /// The document of the account, `null` when the device holds none.
  Future<CrdtDocument?> _documentOf(String documentId) async {
    final DocumentSnapshot? snapshot = await _snapshots.read(
      DocumentId(documentId),
    );
    if (snapshot == null) return null;
    return snapshot.restore();
  }
}
