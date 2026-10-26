import 'package:limpid_app/src/data/account_op_queue_store.dart';
import 'package:limpid_app/src/data/account_snapshot_store.dart';
import 'package:limpid_app/src/data/app_database.dart';
import 'package:limpid_app/src/data/published_book_reader.dart';
import 'package:limpid_app/src/domain/repositories.dart';
import 'package:limpid_app/src/domain/scene_metadata.dart';
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
      accountId: _currentAuthor().value,
    );
    for (final String documentId in documents) {
      await _snapshots.remove(DocumentId(documentId));
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
    await database.manuscripts.saveScene(
      saved,
      projectId: projectId,
      accountId: _currentAuthor().value,
    );
    return saved;
  }

  @override
  Future<List<Series>> listSeries(String projectId) =>
      database.manuscripts.listSeries(projectId);

  @override
  Future<Series> createSeries({
    required String projectId,
    required String title,
    String synopsis = '',
  }) async {
    final DateTime now = _now();
    final List<Series> existing = await database.manuscripts.listSeries(
      projectId,
    );
    final Series series = Series(
      id: SeriesId(_ids.generate().value),
      projectId: ProjectId(projectId),
      title: title,
      synopsis: synopsis,
      order: _nextOrder(existing.map((Series item) => item.order)),
      createdAt: now,
      updatedAt: now,
    );
    await database.manuscripts.saveSeries(series, projectId: projectId);
    await _attachSeries(projectId, series.id);
    return series;
  }

  @override
  Future<List<Volume>> listVolumes(String seriesId) =>
      database.manuscripts.listVolumes(seriesId);

  @override
  Future<List<Chapter>> listChaptersOfVolume(String volumeId) =>
      database.manuscripts.listChaptersOfVolume(volumeId);

  @override
  Future<Volume> createVolume({
    required String seriesId,
    required String title,
    String synopsis = '',
  }) async {
    final DateTime now = _now();
    final String? projectId = await database.manuscripts.resolveSeriesProject(
      seriesId,
    );
    final List<Volume> existing = await database.manuscripts.listVolumes(
      seriesId,
    );
    final Volume volume = Volume(
      id: VolumeId(_ids.generate().value),
      seriesId: SeriesId(seriesId),
      title: title,
      synopsis: synopsis,
      order: _nextOrder(existing.map((Volume item) => item.order)),
      createdAt: now,
      updatedAt: now,
    );
    await database.manuscripts.saveVolume(volume, projectId: projectId);
    await _attachVolume(seriesId, volume.id);
    return volume;
  }

  @override
  Future<Chapter> createChapter({
    required String projectId,
    String? volumeId,
    required String title,
    String synopsis = '',
  }) async {
    final DateTime now = _now();
    final List<Chapter> existing = await database.manuscripts.listChapters(
      projectId,
    );
    final Chapter chapter = Chapter(
      id: ChapterId(_ids.generate().value),
      volumeId: volumeId == null ? null : VolumeId(volumeId),
      title: title,
      synopsis: synopsis,
      order: _nextOrder(existing.map((Chapter item) => item.order)),
      createdAt: now,
      updatedAt: now,
    );
    await database.manuscripts.saveChapter(chapter, projectId: projectId);
    await _attachChapter(projectId, chapter.id);
    final String? volume = volumeId;
    if (volume != null) {
      await _attachChapterToVolume(volume, chapter.id);
    }
    return chapter;
  }

  @override
  Future<Scene> createScene({
    required String chapterId,
    required String title,
    String synopsis = '',
  }) async {
    final DateTime now = _now();
    final String sceneId = _ids.generate().value;
    final DocumentId documentId = DocumentId(sceneId);
    final List<Scene> existing = await database.manuscripts.listScenes(
      chapterId,
    );
    final Scene scene = Scene(
      id: SceneId(sceneId),
      chapterId: ChapterId(chapterId),
      documentId: documentId,
      title: title,
      synopsis: synopsis,
      order: _nextOrder(existing.map((Scene item) => item.order)),
      createdAt: now,
      updatedAt: now,
    );
    await database.manuscripts.saveScene(
      scene,
      accountId: _currentAuthor().value,
    );

    // La scene nait avec son titre dans son document : elle est une vraie
    // scene, elle se retrouve apres le redemarrage et elle se synchronise
    // comme tout le reste de l'ecriture.
    await applyOperations(<SyncOp>[
      SetMetaOp(
        doc: documentId,
        lamport: await _nextLamport(documentId),
        author: _currentAuthor(),
        key: sceneTitleMetaKey,
        value: title,
      ),
    ]);
    return scene;
  }

  @override
  Future<Scene> moveScene({
    required String sceneId,
    required int targetIndex,
  }) async {
    final Scene? scene = await database.manuscripts.findScene(sceneId);
    if (scene == null) {
      throw StateError('The scene "$sceneId" does not exist.');
    }
    final List<Scene> siblings = await database.manuscripts.listScenes(
      scene.chapterId.value,
    );
    final List<Scene> remaining = siblings
        .where((Scene item) => item.id.value != sceneId)
        .toList(growable: false);
    final int index = targetIndex.clamp(0, remaining.length);
    final OrderKey? lower = index == 0 ? null : remaining[index - 1].order;
    final OrderKey? upper = index == remaining.length
        ? null
        : remaining[index].order;

    final Scene moved = scene.copyWith(
      order: OrderKey.between(lower, upper),
      updatedAt: _now(),
    );
    await database.manuscripts.saveScene(
      moved,
      accountId: _currentAuthor().value,
    );

    // L'operation porte l'index fractionnaire et rien d'autre : le texte
    // de la scene ne bouge pas.
    await applyOperations(<SyncOp>[
      SetMetaOp(
        doc: moved.documentId,
        lamport: await _nextLamport(moved.documentId),
        author: _currentAuthor(),
        key: sceneOrderMetaKey,
        value: moved.order.value,
      ),
    ]);
    return moved;
  }

  @override
  Future<CrdtDocument> loadDocument(String documentId) async {
    final DocumentSnapshot? snapshot = await _snapshots.read(
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
      await _applySceneOrders(operations);
      final OpQueue queue = _queue;
      for (final SyncOp operation in operations) {
        await queue.enqueue(operation);
      }
    });
  }

  /// Writes the position of the scenes the operations carry.
  ///
  /// The position of a scene is a metadata of its document: an operation
  /// that comes from another device moves the scene here too.
  Future<void> _applySceneOrders(List<SyncOp> operations) async {
    for (final SyncOp operation in operations) {
      if (operation is! SetMetaOp) continue;
      if (operation.key != sceneOrderMetaKey) continue;
      await database.manuscripts.updateSceneOrder(
        operation.doc,
        OrderKey(operation.value),
      );
    }
  }

  /// Applies the operations to the local document and writes the journal.
  ///
  /// The CRDT is idempotent: an operation already known is ignored, so
  /// applying the same operation twice never changes the document.
  Future<void> _applyToDocument(
    DocumentId documentId,
    List<SyncOp> operations,
  ) async {
    final DocumentSnapshot? snapshot = await _snapshots.read(documentId);
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
    await _snapshots.write(
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

  /// Adds a series to the list of a project.
  Future<void> _attachSeries(String projectId, SeriesId seriesId) async {
    final Project? project = await database.manuscripts.findProject(
      projectId,
      _currentAuthor().value,
    );
    if (project == null) return;
    if (project.seriesIds.contains(seriesId)) return;
    await database.manuscripts.saveProject(
      project.copyWith(seriesIds: <SeriesId>[...project.seriesIds, seriesId]),
    );
  }

  /// Adds a volume to the list of a series.
  Future<void> _attachVolume(String seriesId, VolumeId volumeId) async {
    final Series? series = await database.manuscripts.findSeries(seriesId);
    if (series == null) return;
    if (series.volumeIds.contains(volumeId)) return;
    await database.manuscripts.saveSeries(
      series.copyWith(volumeIds: <VolumeId>[...series.volumeIds, volumeId]),
      projectId: series.projectId.value,
    );
  }

  /// Adds a chapter to the list of a volume.
  Future<void> _attachChapterToVolume(
    String volumeId,
    ChapterId chapterId,
  ) async {
    final Volume? volume = await database.manuscripts.findVolume(volumeId);
    if (volume == null) return;
    if (volume.chapterIds.contains(chapterId)) return;
    await database.manuscripts.saveVolume(
      volume.copyWith(chapterIds: <ChapterId>[...volume.chapterIds, chapterId]),
    );
  }

  /// The fractional index that comes after every index of [existing].
  ///
  /// The index is computed strictly after the last one, so an index that
  /// exists is never rewritten: a creation never moves a sibling.
  OrderKey _nextOrder(Iterable<OrderKey> existing) {
    OrderKey? last;
    for (final OrderKey key in existing) {
      if (last == null || key.isAfter(last)) last = key;
    }
    if (last == null) return OrderKey.initial;
    return OrderKey.between(last, null);
  }

  /// The next Lamport timestamp of a document.
  ///
  /// The timestamp is the one of the last operation the document knows,
  /// advanced by one tick: the operation is always newer than the ones that
  /// came before it.
  Future<int> _nextLamport(DocumentId documentId) async {
    final DocumentSnapshot? snapshot = await _snapshots.read(documentId);
    return (snapshot?.maxLamport ?? 0) + 1;
  }

  /// Removes the queued operations of a document.
  ///
  /// Only the operations of the current account are removed: the queue of
  /// the other accounts belongs to them.
  Future<void> _removeQueuedOperations(String documentId) async {
    final AccountOpQueueStore queue = _queueStore;
    final List<QueuedOp> pending = await queue.all();
    final List<String> keys = pending
        .where((QueuedOp entry) => entry.documentId == documentId)
        .map((QueuedOp entry) => entry.operationKey)
        .toList(growable: false);
    if (keys.isEmpty) return;
    await queue.removeAll(keys);
  }

  /// The queue of the operations of the current account.
  AccountOpQueueStore get _queueStore =>
      database.queueFor(() => _currentAuthor().value);

  /// The queue of the operations of the current account, with the retry
  /// policy of `limpid_sync`.
  OpQueue get _queue => OpQueue(store: _queueStore);

  /// The snapshots of the documents of the current account.
  AccountSnapshotStore get _snapshots =>
      database.snapshotsFor(() => _currentAuthor().value);

  /// The highest Lamport timestamp of a journal.
  static int _maxLamport(List<SyncOp> journal) {
    var max = 0;
    for (final SyncOp operation in journal) {
      if (operation.lamport > max) max = operation.lamport;
    }
    return max;
  }
}
