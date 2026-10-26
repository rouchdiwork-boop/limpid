import 'package:limpid_app/src/data/app_database.dart';
import 'package:limpid_app/src/data/published_book_reader.dart';
import 'package:limpid_app/src/domain/repositories.dart';
import 'package:limpid_core/limpid_core.dart';
import 'package:limpid_sync/limpid_sync.dart';

/// The manuscripts of the author, served by the local database.
///
/// The repository is **local first**: it always answers from the SQLite
/// database of the device, never from the network. The network only feeds
/// the queue of the operations and the background refresh.
///
/// ## The link between a project and its chapters
///
/// The contract of the repository does not carry the parent of a chapter:
/// [saveChapter] resolves it from the project that already lists the
/// chapter, and from the single project of the library when there is one.
/// A chapter that no project claims is still written, and it appears as soon
/// as a project lists it.
///
/// ## The account the repository answers for
///
/// The local database is unique per device and outlives the session: the
/// reads are therefore scoped to the author who is signed in. The scope
/// follows [currentAuthor], which the composition root may resolve from the
/// live session — the author of the constructor is the scope when the
/// resolver is not given.
final class LocalManuscriptRepository
    implements ManuscriptRepository, PublishedBookReader {
  /// Creates a repository on top of [database].
  LocalManuscriptRepository({
    required this.database,
    required this.author,
    AuthorId Function()? currentAuthor,
    DateTime Function()? now,
    UlidGenerator? ids,
  }) : _currentAuthor = currentAuthor ?? (() => author),
       _now = now ?? DateTime.now,
       _ids = ids ?? UlidGenerator();

  /// The local database of the application.
  final AppDatabase database;

  /// The author of the local operations.
  final AuthorId author;

  final AuthorId Function() _currentAuthor;
  final DateTime Function() _now;
  final UlidGenerator _ids;

  @override
  Future<List<Project>> listProjects() =>
      database.manuscripts.listProjects(_currentAuthor().value);

  @override
  Future<Project?> findProject(String projectId) =>
      database.manuscripts.findProject(projectId, _currentAuthor().value);

  @override
  Future<Project?> findPublishedProject(String projectId) =>
      database.manuscripts.findPublishedProject(projectId);

  @override
  Future<Project> createProject({
    required String title,
    String? synopsis,
  }) async {
    final DateTime now = _now();
    final Project project = Project(
      id: ProjectId(_ids.generate().value),
      ownerId: _currentAuthor(),
      title: title,
      synopsis: synopsis ?? '',
      order: OrderKey.initial,
      createdAt: now,
      updatedAt: now,
    );
    await database.manuscripts.saveProject(project);
    return project;
  }

  @override
  Future<Project> saveProject(Project project) async {
    final Project saved = project.copyWith(updatedAt: _now());
    await database.manuscripts.saveProject(saved);
    await _recordMembership(saved);
    return saved;
  }

  @override
  Future<void> deleteProject(String projectId) async {
    final List<String> documents = await database.manuscripts.deleteProject(
      projectId,
    );
    for (final String documentId in documents) {
      await database.snapshots.remove(DocumentId(documentId));
      await _removeQueuedOperations(documentId);
    }
  }

  @override
  Future<List<Chapter>> listChapters(String projectId) =>
      database.manuscripts.listChapters(projectId);

  @override
  Future<Chapter> saveChapter(Chapter chapter) async {
    final String? projectId = await _resolveChapterProject(chapter.id.value);
    final Chapter saved = chapter.copyWith(updatedAt: _now());
    await database.manuscripts.saveChapter(saved, projectId: projectId);
    if (projectId != null) {
      await _attachChapter(projectId, chapter.id);
    }
    return saved;
  }

  @override
  Future<List<Scene>> listScenes(String chapterId) =>
      database.manuscripts.listScenes(chapterId);

  @override
  Future<Scene> saveScene(Scene scene) async {
    final String? projectId = await database.manuscripts.resolveChapterProject(
      scene.chapterId.value,
    );
    final Scene saved = scene.copyWith(updatedAt: _now());
    await database.manuscripts.saveScene(saved, projectId: projectId);
    return saved;
  }

  @override
  Future<CrdtDocument> loadDocument(String documentId) async {
    final DocumentSnapshot? snapshot = await database.snapshots.read(
      DocumentId(documentId),
    );
    if (snapshot == null) {
      return CrdtDocument.empty(DocumentId(documentId));
    }
    return snapshot.restore();
  }

  @override
  Future<void> applyOperations(List<SyncOp> operations) async {
    if (operations.isEmpty) return;
    final Map<String, List<SyncOp>> byDocument = <String, List<SyncOp>>{};
    for (final SyncOp operation in operations) {
      byDocument
          .putIfAbsent(operation.doc.value, () => <SyncOp>[])
          .add(operation);
    }
    await database.sync.transaction(() async {
      for (final MapEntry<String, List<SyncOp>> entry in byDocument.entries) {
        await _applyToDocument(DocumentId(entry.key), entry.value);
      }
      for (final SyncOp operation in operations) {
        await database.queue.enqueue(operation);
      }
    });
  }

  /// Applies the operations to the local document and writes the journal.
  ///
  /// The CRDT is idempotent: an operation already known is ignored, so
  /// applying the same operation twice never changes the document.
  Future<void> _applyToDocument(
    DocumentId documentId,
    List<SyncOp> operations,
  ) async {
    final DocumentSnapshot? snapshot = await database.snapshots.read(
      documentId,
    );
    final Set<String> known = snapshot == null
        ? <String>{}
        : snapshot.operations
              .map((SyncOp operation) => operation.operationKey)
              .toSet();
    final List<SyncOp> fresh = operations
        .where((SyncOp operation) => !known.contains(operation.operationKey))
        .toList(growable: false);
    if (fresh.isEmpty) return;

    final CrdtDocument document = snapshot == null
        ? CrdtDocument.empty(documentId)
        : snapshot.restore();
    document.applyAll(fresh);

    final List<SyncOp> journal = snapshot == null
        ? fresh
        : <SyncOp>[...snapshot.operations, ...fresh];
    await database.snapshots.write(
      DocumentSnapshot(
        documentId: documentId,
        since: snapshot?.since ?? 0,
        maxLamport: _maxLamport(journal),
        operations: journal,
      ),
    );
  }

  /// Resolves the project a chapter belongs to.
  Future<String?> _resolveChapterProject(String chapterId) async {
    final String? resolved = await database.manuscripts.resolveChapterProject(
      chapterId,
    );
    if (resolved != null) return resolved;
    final List<Project> projects = await database.manuscripts.listProjects(
      _currentAuthor().value,
    );
    if (projects.length != 1) return null;
    return projects.first.id.value;
  }

  /// Records the membership of the author to the project.
  ///
  /// A project the author does not own is a project the author collaborates
  /// on: the membership keeps it in the library of the author, and it keeps
  /// it out of the library of everybody else.
  Future<void> _recordMembership(Project project) async {
    final AuthorId current = _currentAuthor();
    if (project.ownerId == current) return;
    await database.memberships.add(
      projectId: project.id.value,
      authorId: current.value,
    );
  }

  /// Adds a chapter to the list of a project.
  Future<void> _attachChapter(String projectId, ChapterId chapterId) async {
    final Project? project = await database.manuscripts.findProject(
      projectId,
      _currentAuthor().value,
    );
    if (project == null) return;
    if (project.chapterIds.contains(chapterId)) return;
    await database.manuscripts.saveProject(
      project.copyWith(
        chapterIds: <ChapterId>[...project.chapterIds, chapterId],
      ),
    );
  }

  /// Removes the queued operations of a document.
  Future<void> _removeQueuedOperations(String documentId) async {
    final List<QueuedOp> pending = await database.queueStore.all();
    final List<String> keys = pending
        .where((QueuedOp entry) => entry.documentId == documentId)
        .map((QueuedOp entry) => entry.operationKey)
        .toList(growable: false);
    if (keys.isEmpty) return;
    await database.queueStore.removeAll(keys);
  }

  /// The highest Lamport timestamp of a journal.
  static int _maxLamport(List<SyncOp> journal) {
    var max = 0;
    for (final SyncOp operation in journal) {
      if (operation.lamport > max) max = operation.lamport;
    }
    return max;
  }
}
