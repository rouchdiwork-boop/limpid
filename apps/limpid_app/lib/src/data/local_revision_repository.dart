import 'package:limpid_app/src/data/app_database.dart';
import 'package:limpid_app/src/data/revision_store.dart';
import 'package:limpid_app/src/domain/revision_repository.dart';
import 'package:limpid_core/limpid_core.dart';

/// The discussions of the projects, served by the local database.
///
/// The repository is the durable implementation of the contract of the
/// review: the discussions are written in the SQLite file of the device and
/// read back from it, so they survive the restart of the application.
///
/// The **anchors** are not stored here: they are marks of the CRDT, and the
/// document carries them. The repository only holds the conversation itself.
final class LocalRevisionRepository implements RevisionRepository {
  /// Creates a repository on top of [database].
  LocalRevisionRepository({required AppDatabase database})
    : _store = RevisionStore(database.sync);

  final RevisionStore _store;

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
}
