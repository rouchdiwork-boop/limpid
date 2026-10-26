import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:limpid_app/src/data/local_account_scope.dart';
import 'package:limpid_app/src/data/project_identity_store.dart';
import 'package:limpid_core/limpid_core.dart';
import 'package:limpid_sync/limpid_sync.dart';

/// The link between a synchronised document and the project that owns it.
typedef DocumentBinding = ({String documentId, String projectId});

/// The state the interface displays, stored in the local database.
///
/// Every statement is parameterised: the values never reach the SQL text.
///
/// ## The scope of the author
///
/// The local database is unique per device and is **not** wiped when the
/// author signs out: the reads of the projects are therefore scoped to the
/// author who is signed in. A project is visible when the author owns it, or
/// when the local database knows the author collaborates on it — the
/// ownership alone would hide the projects of a collaborator.
///
/// ## The scope of the account
///
/// The tables that carry the data of an account — the preferences, the index
/// of the documents and the cursors of the synchronisation — are scoped to
/// the account of the session: the local database is shared by every
/// account of the device, and the data of one account must never be served
/// to another. The reads that name an account explicitly use it; the others
/// fall back on the account of the session.
final class ManuscriptStore {
  /// Creates a store on top of [database].
  ManuscriptStore(this._database, this._account);

  /// The Drift database holding the tables.
  final SyncDatabase _database;

  /// The account that owns the local data of the device.
  final LocalAccountScope _account;

  /// The identifier of the account that owns the local data right now.
  String get accountId => _account.accountId;

  /// The predicate that scopes a read of the projects to an author.
  ///
  /// The predicate holds no value: the author is always bound to the two
  /// placeholders it declares.
  static const String _scope =
      '(owner_id = ? OR id IN ('
      'SELECT project_id FROM project_members WHERE author_id = ?))';

  /// The projects of the author, most recently updated first.
  ///
  /// The projects of the other authors are never returned: the local
  /// database is shared by every author who uses the device.
  Future<List<Project>> listProjects(String authorId) async {
    final List<Map<String, Object?>> rows = await _select(
      'SELECT * FROM projects WHERE $_scope '
      'ORDER BY updated_at DESC, id ASC',
      <Object?>[authorId, authorId],
    );
    return List<Project>.unmodifiable(rows.map(_projectOf));
  }

  /// The project of [projectId], `null` when it does not exist.
  ///
  /// The project of another author is invisible: it is `null`, as if it were
  /// never written on the device.
  Future<Project?> findProject(String projectId, String authorId) async {
    final Map<String, Object?>? row = await _selectOne(
      'SELECT * FROM projects WHERE id = ? AND $_scope',
      <Object?>[projectId, authorId, authorId],
    );
    return row == null ? null : _projectOf(row);
  }

  /// The published project of [projectId], `null` when there is none.
  ///
  /// A published book is public: the read ignores the author, and it only
  /// answers for a book in the `published` stage.
  Future<Project?> findPublishedProject(String projectId) async {
    // La même règle que le serveur (D-33) : un livre n'a de page publique
    // que s'il est **publié** et **en vitrine**. Le repli local ne doit pas
    // montrer un livre que le serveur refuse de montrer.
    final Map<String, Object?>? row = await _selectOne(
      'SELECT * FROM projects WHERE id = ? AND status = ? AND is_public = 1',
      <Object?>[projectId, ManuscriptStatus.published.name],
    );
    return row == null ? null : _projectOf(row);
  }

  /// The number of projects of the library of the author.
  Future<int> countProjects(String authorId) async {
    final Map<String, Object?>? row = await _selectOne(
      'SELECT COUNT(*) AS total FROM projects WHERE $_scope',
      <Object?>[authorId, authorId],
    );
    return row == null ? 0 : _integer(row, 'total');
  }

  /// Writes the metadata of a project and reconciles its chapters.
  ///
  /// The chapters the project lists are attached to it, so the link between
  /// a project and its chapters is the same whichever side is written first.
  Future<void> saveProject(Project project) async {
    // Le serveur fabrique l'identifiant d'un projet et l'appareil l'adopte
    // quand il diffère du sien : une écriture qui porte encore l'ancien
    // identifiant doit atterrir sur le projet lui-même, jamais en créer un
    // second.
    final String projectId = await _canonicalId(project.id.value);
    await _execute(
      '''
INSERT INTO projects (
  id, owner_id, title, synopsis, status, order_key, is_public,
  series_ids, chapter_ids, created_at, updated_at
) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
ON CONFLICT(id) DO UPDATE SET
  owner_id = excluded.owner_id,
  title = excluded.title,
  synopsis = excluded.synopsis,
  status = excluded.status,
  order_key = excluded.order_key,
  is_public = excluded.is_public,
  series_ids = excluded.series_ids,
  chapter_ids = excluded.chapter_ids,
  updated_at = excluded.updated_at''',
      <Object?>[
        projectId,
        project.ownerId.value,
        project.title,
        project.synopsis,
        project.status.name,
        project.order.value,
        project.isPublic ? 1 : 0,
        jsonEncode(project.seriesIds.map((SeriesId id) => id.value).toList()),
        jsonEncode(project.chapterIds.map((ChapterId id) => id.value).toList()),
        _milliseconds(project.createdAt),
        _milliseconds(project.updatedAt),
      ],
    );
    await _attachChapters(projectId, project.chapterIds);
  }

  /// The identifier the project [projectId] was renamed to.
  ///
  /// The server mints the identifier of a project and the device adopts it:
  /// the alias remembers the former identifier, so a write that still carries
  /// it lands on the project itself.
  ///
  /// The alias is a fact about the identifiers of the device: it is shared
  /// by every account that collaborates on the project.
  Future<String> _canonicalId(String projectId) async {
    final String? alias = await readPreference(
      '$projectAliasKeyPrefix$projectId',
      accountId: deviceAliasAccountId,
    );
    return alias ?? projectId;
  }

  /// The series of a project, in reading order.
  ///
  /// The order of the `seriesIds` of the project wins; the series the
  /// project does not list are appended, sorted by their order key.
  Future<List<Series>> listSeries(String projectId) async {
    final Map<String, Object?>? project = await _selectOne(
      'SELECT series_ids FROM projects WHERE id = ?',
      <Object?>[projectId],
    );
    final List<String> declared = project == null
        ? const <String>[]
        : _strings(project, 'series_ids');

    final List<Map<String, Object?>> rows = await _select(
      'SELECT * FROM series WHERE project_id = ? ORDER BY order_key ASC, id ASC',
      <Object?>[projectId],
    );
    return List<Series>.unmodifiable(
      await _orderedBy('series', declared, rows, _seriesOf),
    );
  }

  /// The series of [seriesId], `null` when it does not exist.
  Future<Series?> findSeries(String seriesId) async {
    final Map<String, Object?>? row = await _selectOne(
      'SELECT * FROM series WHERE id = ?',
      <Object?>[seriesId],
    );
    return row == null ? null : _seriesOf(row);
  }

  /// Writes a series and attaches it to [projectId].
  ///
  /// When [projectId] is `null` the owner is resolved with
  /// [resolveSeriesProject]: the series stays unattached when no project
  /// claims it.
  Future<void> saveSeries(Series series, {String? projectId}) async {
    await _execute(
      '''
INSERT INTO series (
  id, project_id, title, synopsis, order_key, volume_ids, created_at, updated_at
) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
ON CONFLICT(id) DO UPDATE SET
  project_id = excluded.project_id,
  title = excluded.title,
  synopsis = excluded.synopsis,
  order_key = excluded.order_key,
  volume_ids = excluded.volume_ids,
  updated_at = excluded.updated_at''',
      <Object?>[
        series.id.value,
        projectId ?? '',
        series.title,
        series.synopsis,
        series.order.value,
        jsonEncode(series.volumeIds.map((VolumeId id) => id.value).toList()),
        _milliseconds(series.createdAt),
        _milliseconds(series.updatedAt),
      ],
    );
  }

  /// The project a series belongs to, `null` when it is not attached yet.
  ///
  /// The link is resolved from the series itself first, then from the
  /// projects that already list the series.
  Future<String?> resolveSeriesProject(String seriesId) async {
    final Map<String, Object?>? row = await _selectOne(
      'SELECT project_id FROM series WHERE id = ?',
      <Object?>[seriesId],
    );
    final String? stored = row == null ? null : _text(row, 'project_id');
    if (stored != null && stored.isNotEmpty) return stored;

    final List<Map<String, Object?>> projects = await _select(
      'SELECT id, series_ids FROM projects',
    );
    for (final Map<String, Object?> project in projects) {
      if (_strings(project, 'series_ids').contains(seriesId)) {
        return _text(project, 'id');
      }
    }
    return null;
  }

  /// The volumes of a series, in reading order.
  ///
  /// The order of the `volumeIds` of the series wins; the volumes the
  /// series does not list are appended, sorted by their order key.
  Future<List<Volume>> listVolumes(String seriesId) async {
    final Map<String, Object?>? series = await _selectOne(
      'SELECT volume_ids FROM series WHERE id = ?',
      <Object?>[seriesId],
    );
    final List<String> declared = series == null
        ? const <String>[]
        : _strings(series, 'volume_ids');

    final List<Map<String, Object?>> rows = await _select(
      'SELECT * FROM volumes WHERE series_id = ? ORDER BY order_key ASC, id ASC',
      <Object?>[seriesId],
    );
    return List<Volume>.unmodifiable(
      await _orderedBy('volumes', declared, rows, _volumeOf),
    );
  }

  /// The volume of [volumeId], `null` when it does not exist.
  Future<Volume?> findVolume(String volumeId) async {
    final Map<String, Object?>? row = await _selectOne(
      'SELECT * FROM volumes WHERE id = ?',
      <Object?>[volumeId],
    );
    return row == null ? null : _volumeOf(row);
  }

  /// Writes a volume and attaches it to [seriesId].
  ///
  /// The project of the volume is the one of its series: it is denormalised
  /// so that the purge and the reads of the library find the book of a
  /// volume without walking the whole hierarchy.
  Future<void> saveVolume(Volume volume, {String? projectId}) async {
    await _execute(
      '''
INSERT INTO volumes (
  id, series_id, project_id, title, synopsis, order_key, chapter_ids,
  created_at, updated_at
) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
ON CONFLICT(id) DO UPDATE SET
  series_id = excluded.series_id,
  project_id = excluded.project_id,
  title = excluded.title,
  synopsis = excluded.synopsis,
  order_key = excluded.order_key,
  chapter_ids = excluded.chapter_ids,
  updated_at = excluded.updated_at''',
      <Object?>[
        volume.id.value,
        volume.seriesId.value,
        projectId ?? '',
        volume.title,
        volume.synopsis,
        volume.order.value,
        jsonEncode(volume.chapterIds.map((ChapterId id) => id.value).toList()),
        _milliseconds(volume.createdAt),
        _milliseconds(volume.updatedAt),
      ],
    );
  }

  /// The chapters of a project, in reading order.
  ///
  /// The order of the `chapterIds` of the project wins; the chapters the
  /// project does not list are appended, sorted by their order key.
  Future<List<Chapter>> listChapters(String projectId) async {
    final Map<String, Object?>? project = await _selectOne(
      'SELECT chapter_ids FROM projects WHERE id = ?',
      <Object?>[projectId],
    );
    final List<String> declared = project == null
        ? const <String>[]
        : _strings(project, 'chapter_ids');

    final List<Map<String, Object?>> rows = await _select(
      'SELECT * FROM chapters WHERE project_id = ? ORDER BY order_key ASC, id ASC',
      <Object?>[projectId],
    );
    return List<Chapter>.unmodifiable(
      await _orderedBy('chapters', declared, rows, _chapterOf),
    );
  }

  /// The chapters of a volume, in reading order.
  ///
  /// The order of the `chapterIds` of the volume wins; the chapters the
  /// volume does not list are appended, sorted by their order key.
  Future<List<Chapter>> listChaptersOfVolume(String volumeId) async {
    final Map<String, Object?>? volume = await _selectOne(
      'SELECT chapter_ids FROM volumes WHERE id = ?',
      <Object?>[volumeId],
    );
    final List<String> declared = volume == null
        ? const <String>[]
        : _strings(volume, 'chapter_ids');

    final List<Map<String, Object?>> rows = await _select(
      'SELECT * FROM chapters WHERE volume_id = ? ORDER BY order_key ASC, id ASC',
      <Object?>[volumeId],
    );
    return List<Chapter>.unmodifiable(
      await _orderedBy('chapters', declared, rows, _chapterOf),
    );
  }

  /// The chapter of [chapterId], `null` when it does not exist.
  Future<Chapter?> findChapter(String chapterId) async {
    final Map<String, Object?>? row = await _selectOne(
      'SELECT * FROM chapters WHERE id = ?',
      <Object?>[chapterId],
    );
    return row == null ? null : _chapterOf(row);
  }

  /// The project a chapter belongs to, `null` when it is not attached yet.
  ///
  /// The link is resolved from the chapter itself first, then from the
  /// projects that already list the chapter.
  Future<String?> resolveChapterProject(String chapterId) async {
    final Map<String, Object?>? row = await _selectOne(
      'SELECT project_id FROM chapters WHERE id = ?',
      <Object?>[chapterId],
    );
    final String? stored = row == null ? null : _text(row, 'project_id');
    if (stored != null && stored.isNotEmpty) return stored;

    final List<Map<String, Object?>> projects = await _select(
      'SELECT id, chapter_ids FROM projects',
    );
    for (final Map<String, Object?> project in projects) {
      if (_strings(project, 'chapter_ids').contains(chapterId)) {
        return _text(project, 'id');
      }
    }
    return null;
  }

  /// Writes a chapter and attaches it to [projectId].
  ///
  /// When [projectId] is `null` the owner is resolved with
  /// [resolveChapterProject]: the chapter stays unattached when no project
  /// claims it.
  Future<void> saveChapter(Chapter chapter, {String? projectId}) async {
    await _execute(
      '''
INSERT INTO chapters (
  id, project_id, volume_id, title, synopsis, status, order_key,
  scene_ids, target_word_count, created_at, updated_at
) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
ON CONFLICT(id) DO UPDATE SET
  project_id = excluded.project_id,
  volume_id = excluded.volume_id,
  title = excluded.title,
  synopsis = excluded.synopsis,
  status = excluded.status,
  order_key = excluded.order_key,
  scene_ids = excluded.scene_ids,
  target_word_count = excluded.target_word_count,
  updated_at = excluded.updated_at''',
      <Object?>[
        chapter.id.value,
        projectId ?? '',
        chapter.volumeId?.value,
        chapter.title,
        chapter.synopsis,
        chapter.status.name,
        chapter.order.value,
        jsonEncode(chapter.sceneIds.map((SceneId id) => id.value).toList()),
        chapter.targetWordCount,
        _milliseconds(chapter.createdAt),
        _milliseconds(chapter.updatedAt),
      ],
    );
  }

  /// The scenes of a chapter, in reading order.
  Future<List<Scene>> listScenes(String chapterId) async {
    final List<Map<String, Object?>> rows = await _select(
      'SELECT * FROM scenes WHERE chapter_id = ? ORDER BY order_key ASC, id ASC',
      <Object?>[chapterId],
    );
    return List<Scene>.unmodifiable(rows.map(_sceneOf));
  }

  /// The scene of [sceneId], `null` when it does not exist.
  Future<Scene?> findScene(String sceneId) async {
    final Map<String, Object?>? row = await _selectOne(
      'SELECT * FROM scenes WHERE id = ?',
      <Object?>[sceneId],
    );
    return row == null ? null : _sceneOf(row);
  }

  /// Writes a scene and indexes its CRDT document.
  ///
  /// The document of the scene is routed to the project of its chapter, so
  /// the synchronisation can address the right route of the API.
  ///
  /// The index of the document belongs to the account of [accountId]: the
  /// document of an account is never routed to the project of another.
  Future<void> saveScene(
    Scene scene, {
    String? projectId,
    String? accountId,
  }) async {
    await _execute(
      '''
INSERT INTO scenes (
  id, chapter_id, document_id, title, synopsis, status, order_key,
  point_of_view, word_count, target_word_count, created_at, updated_at
) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
ON CONFLICT(id) DO UPDATE SET
  chapter_id = excluded.chapter_id,
  document_id = excluded.document_id,
  title = excluded.title,
  synopsis = excluded.synopsis,
  status = excluded.status,
  order_key = excluded.order_key,
  point_of_view = excluded.point_of_view,
  word_count = excluded.word_count,
  target_word_count = excluded.target_word_count,
  updated_at = excluded.updated_at''',
      <Object?>[
        scene.id.value,
        scene.chapterId.value,
        scene.documentId.value,
        scene.title,
        scene.synopsis,
        scene.status.name,
        scene.order.value,
        scene.pointOfView?.value,
        scene.wordCount,
        scene.targetWordCount,
        _milliseconds(scene.createdAt),
        _milliseconds(scene.updatedAt),
      ],
    );
    final String? owner =
        projectId ?? await resolveChapterProject(scene.chapterId.value);
    if (owner == null || owner.isEmpty) return;
    await indexDocument(
      documentId: scene.documentId.value,
      sceneId: scene.id.value,
      projectId: owner,
      accountId: accountId,
    );
  }

  /// Writes the position of the scene that owns [documentId].
  ///
  /// The position is the fractional index of the scene in its chapter: an
  /// operation that comes from another device writes it here.
  Future<void> updateSceneOrder(DocumentId documentId, OrderKey order) async {
    await _execute(
      'UPDATE scenes SET order_key = ? WHERE document_id = ?',
      <Object?>[order.value, documentId.value],
    );
  }

  /// Records the project a synchronised document belongs to.
  ///
  /// The index belongs to the account of [accountId]: the document of an
  /// account is never routed to the project of another.
  Future<void> indexDocument({
    required String documentId,
    required String sceneId,
    required String projectId,
    String? accountId,
  }) async {
    await _execute(
      '''
INSERT INTO document_index (
  account_id, document_id, scene_id, project_id, updated_at
) VALUES (?, ?, ?, ?, ?)
ON CONFLICT(account_id, document_id) DO UPDATE SET
  scene_id = excluded.scene_id,
  project_id = excluded.project_id,
  updated_at = excluded.updated_at''',
      <Object?>[
        accountId ?? _account.accountId,
        documentId,
        sceneId,
        projectId,
        DateTime.now().millisecondsSinceEpoch,
      ],
    );
  }

  /// The project a synchronised document belongs to.
  ///
  /// The answer is the one of the account of [accountId]: the index of the
  /// documents is cloisonné par compte.
  Future<String?> findProjectOfDocument(
    String documentId, {
    String? accountId,
  }) async {
    final Map<String, Object?>? row = await _selectOne(
      'SELECT project_id FROM document_index '
      'WHERE account_id = ? AND document_id = ?',
      <Object?>[accountId ?? _account.accountId, documentId],
    );
    if (row == null) return null;
    final String projectId = _text(row, 'project_id');
    return projectId.isEmpty ? null : projectId;
  }

  /// Every synchronised document of the library, with its project.
  ///
  /// The documents of the projects of the other authors are left out: the
  /// synchronisation of a device must never push the manuscript of another
  /// author to the account of the author who is signed in.
  ///
  /// The same document may be indexed by several accounts — a book shared
  /// with a collaborator — and it is therefore returned once.
  Future<List<DocumentBinding>> listDocumentBindings(String authorId) async {
    final List<Map<String, Object?>> rows = await _select(
      'SELECT DISTINCT document_id, project_id FROM document_index '
      'WHERE project_id IN (SELECT id FROM projects WHERE $_scope) '
      'ORDER BY document_id ASC',
      <Object?>[authorId, authorId],
    );
    return List<DocumentBinding>.unmodifiable(
      rows.map(
        (Map<String, Object?> row) => (
          documentId: _text(row, 'document_id'),
          projectId: _text(row, 'project_id'),
        ),
      ),
    );
  }

  /// The Lamport cursor of a document, `0` when it was never pulled.
  ///
  /// The cursor belongs to the account of [accountId]: the scan of the
  /// server never continues the scan of another account.
  Future<int> readCursor(String documentId, {String? accountId}) async {
    final Map<String, Object?>? row = await _selectOne(
      'SELECT lamport FROM sync_cursors '
      'WHERE account_id = ? AND document_id = ?',
      <Object?>[accountId ?? _account.accountId, documentId],
    );
    return row == null ? 0 : _integer(row, 'lamport');
  }

  /// Writes the Lamport cursor of a document.
  Future<void> writeCursor(
    String documentId,
    int lamport, {
    String? accountId,
  }) async {
    await _execute(
      '''
INSERT INTO sync_cursors (account_id, document_id, lamport) VALUES (?, ?, ?)
ON CONFLICT(account_id, document_id) DO UPDATE SET lamport = excluded.lamport''',
      <Object?>[accountId ?? _account.accountId, documentId, lamport],
    );
  }

  /// The value of a preference, `null` when it was never recorded.
  ///
  /// The preference belongs to the account of [accountId]: the preferences of
  /// an account are never shown to another.
  Future<String?> readPreference(String key, {String? accountId}) async {
    final Map<String, Object?>? row = await _selectOne(
      'SELECT value FROM preferences WHERE account_id = ? AND key = ?',
      <Object?>[accountId ?? _account.accountId, key],
    );
    return row == null ? null : _text(row, 'value');
  }

  /// Writes the value of a preference.
  Future<void> writePreference(
    String key,
    String value, {
    String? accountId,
  }) async {
    await _execute(
      '''
INSERT INTO preferences (account_id, key, value) VALUES (?, ?, ?)
ON CONFLICT(account_id, key) DO UPDATE SET value = excluded.value''',
      <Object?>[accountId ?? _account.accountId, key, value],
    );
  }

  /// Removes a project, its series, its volumes, its chapters, its scenes
  /// and its documents.
  ///
  /// The caller removes the CRDT snapshots and the queued operations of the
  /// documents: this store only knows the relational state.
  ///
  /// The index of the documents is scoped to the account of [accountId]: the
  /// documents of another account are left alone.
  Future<List<String>> deleteProject(
    String projectId, {
    String? accountId,
  }) async {
    final String account = accountId ?? _account.accountId;
    final List<Map<String, Object?>> documents = await _select(
      'SELECT document_id FROM document_index '
      'WHERE account_id = ? AND project_id = ?',
      <Object?>[account, projectId],
    );
    final List<String> documentIds = documents
        .map((Map<String, Object?> row) => _text(row, 'document_id'))
        .where((String id) => id.isNotEmpty)
        .toList(growable: false);

    await _execute(
      'DELETE FROM scenes WHERE chapter_id IN '
      '(SELECT id FROM chapters WHERE project_id = ?)',
      <Object?>[projectId],
    );
    await _execute('DELETE FROM chapters WHERE project_id = ?', <Object?>[
      projectId,
    ]);
    await _execute('DELETE FROM volumes WHERE project_id = ?', <Object?>[
      projectId,
    ]);
    await _execute('DELETE FROM series WHERE project_id = ?', <Object?>[
      projectId,
    ]);
    await _execute(
      'DELETE FROM document_index WHERE account_id = ? AND project_id = ?',
      <Object?>[account, projectId],
    );
    await _execute('DELETE FROM projects WHERE id = ?', <Object?>[projectId]);
    return List<String>.unmodifiable(documentIds);
  }

  /// Orders the rows of a level by the children its parent declares.
  ///
  /// The children the parent declares come first, in the order of the
  /// declaration; the others are appended, sorted by their order key. A
  /// declared child that the table does not hold yet is read by its
  /// identifier: the link between a parent and its children is the same
  /// whichever side is written first.
  Future<List<T>> _orderedBy<T>(
    String table,
    List<String> declared,
    List<Map<String, Object?>> rows,
    T Function(Map<String, Object?> row) read,
  ) async {
    final Map<String, Map<String, Object?>> known =
        <String, Map<String, Object?>>{
          for (final Map<String, Object?> row in rows) _text(row, 'id'): row,
        };
    for (final String id in declared) {
      if (known.containsKey(id)) continue;
      final Map<String, Object?>? row = await _selectOne(
        'SELECT * FROM $table WHERE id = ?',
        <Object?>[id],
      );
      if (row != null) known[id] = row;
    }

    final List<T> ordered = <T>[];
    final Set<String> taken = <String>{};
    for (final String id in declared) {
      final Map<String, Object?>? row = known[id];
      if (row == null) continue;
      ordered.add(read(row));
      taken.add(id);
    }
    final List<Map<String, Object?>> remaining =
        known.entries
            .where(
              (MapEntry<String, Map<String, Object?>> entry) =>
                  !taken.contains(entry.key),
            )
            .map((MapEntry<String, Map<String, Object?>> entry) => entry.value)
            .toList(growable: false)
          ..sort(_byOrderKey);
    ordered.addAll(remaining.map(read));
    return ordered;
  }

  /// Attaches the chapters a project lists to that project.
  Future<void> _attachChapters(
    String projectId,
    List<ChapterId> chapters,
  ) async {
    for (final ChapterId chapter in chapters) {
      await _execute(
        'UPDATE chapters SET project_id = ? WHERE id = ? AND '
        '(project_id = ? OR project_id = ?)',
        <Object?>[projectId, chapter.value, projectId, ''],
      );
    }
  }

  /// Reads the rows matching [sql].
  Future<List<Map<String, Object?>>> _select(
    String sql, [
    List<Object?> args = const <Object?>[],
  ]) async {
    final List<QueryRow> rows = await _database
        .customSelect(sql, variables: _variables(args))
        .get();
    return rows.map((QueryRow row) => row.data).toList(growable: false);
  }

  /// Reads the first row matching [sql], `null` when there is none.
  Future<Map<String, Object?>?> _selectOne(
    String sql, [
    List<Object?> args = const <Object?>[],
  ]) async {
    final List<Map<String, Object?>> rows = await _select(sql, args);
    return rows.isEmpty ? null : rows.first;
  }

  /// Runs a statement that writes.
  Future<void> _execute(String sql, List<Object?> args) async {
    await _database.customStatement(sql, args);
  }

  /// Builds the variables of a parameterised statement.
  List<Variable<Object>> _variables(List<Object?> args) =>
      args.map(_variable).toList(growable: false);

  /// Builds the variable holding [value].
  Variable<Object> _variable(Object? value) => switch (value) {
    final String text => Variable<String>(text),
    final int number => Variable<int>(number),
    final bool flag => Variable<bool>(flag),
    final double number => Variable<double>(number),
    null => const Variable<String>(null),
    _ => throw ArgumentError.value(
      value,
      'value',
      'Only text, numbers, booleans and null can be bound to a statement.',
    ),
  };

  /// Reads a project from its row.
  Project _projectOf(Map<String, Object?> row) => Project(
    id: ProjectId(_text(row, 'id')),
    ownerId: AuthorId(_text(row, 'owner_id')),
    title: _text(row, 'title'),
    synopsis: _text(row, 'synopsis'),
    status: _statusOf(row, 'status'),
    isPublic: _boolean(row, 'is_public'),
    order: OrderKey(_text(row, 'order_key')),
    seriesIds: _identifiers<SeriesTag>(_strings(row, 'series_ids')),
    chapterIds: _identifiers<ChapterTag>(_strings(row, 'chapter_ids')),
    createdAt: _date(row, 'created_at'),
    updatedAt: _date(row, 'updated_at'),
  );

  /// Reads a series from its row.
  Series _seriesOf(Map<String, Object?> row) => Series(
    id: SeriesId(_text(row, 'id')),
    projectId: ProjectId(_text(row, 'project_id')),
    title: _text(row, 'title'),
    synopsis: _text(row, 'synopsis'),
    order: OrderKey(_text(row, 'order_key')),
    volumeIds: _identifiers<VolumeTag>(_strings(row, 'volume_ids')),
    createdAt: _date(row, 'created_at'),
    updatedAt: _date(row, 'updated_at'),
  );

  /// Reads a volume from its row.
  Volume _volumeOf(Map<String, Object?> row) => Volume(
    id: VolumeId(_text(row, 'id')),
    seriesId: SeriesId(_text(row, 'series_id')),
    title: _text(row, 'title'),
    synopsis: _text(row, 'synopsis'),
    order: OrderKey(_text(row, 'order_key')),
    chapterIds: _identifiers<ChapterTag>(_strings(row, 'chapter_ids')),
    createdAt: _date(row, 'created_at'),
    updatedAt: _date(row, 'updated_at'),
  );

  /// Reads a chapter from its row.
  Chapter _chapterOf(Map<String, Object?> row) => Chapter(
    id: ChapterId(_text(row, 'id')),
    volumeId: _optionalId<VolumeTag>(_text(row, 'volume_id')),
    title: _text(row, 'title'),
    synopsis: _text(row, 'synopsis'),
    status: _statusOf(row, 'status'),
    order: OrderKey(_text(row, 'order_key')),
    sceneIds: _identifiers<SceneTag>(_strings(row, 'scene_ids')),
    targetWordCount: _integer(row, 'target_word_count'),
    createdAt: _date(row, 'created_at'),
    updatedAt: _date(row, 'updated_at'),
  );

  /// Reads a scene from its row.
  Scene _sceneOf(Map<String, Object?> row) => Scene(
    id: SceneId(_text(row, 'id')),
    chapterId: ChapterId(_text(row, 'chapter_id')),
    documentId: DocumentId(_text(row, 'document_id')),
    title: _text(row, 'title'),
    synopsis: _text(row, 'synopsis'),
    status: _statusOf(row, 'status'),
    order: OrderKey(_text(row, 'order_key')),
    pointOfView: _optionalId<CharacterTag>(_text(row, 'point_of_view')),
    wordCount: _integer(row, 'word_count'),
    targetWordCount: _integer(row, 'target_word_count'),
    createdAt: _date(row, 'created_at'),
    updatedAt: _date(row, 'updated_at'),
  );

  /// Reads a column of text, an empty string when it is missing.
  static String _text(Map<String, Object?> row, String column) {
    final Object? value = row[column];
    return value is String ? value : '';
  }

  /// Reads a column of integers, `0` when it is missing.
  static int _integer(Map<String, Object?> row, String column) {
    final Object? value = row[column];
    return value is int ? value : 0;
  }

  /// Reads a column holding a boolean, `false` when it is missing.
  ///
  /// SQLite stores the booleans as integers: `1` is true, `0` is false.
  static bool _boolean(Map<String, Object?> row, String column) {
    final Object? value = row[column];
    return value is int && value != 0;
  }

  /// Reads a column of timestamps.
  static DateTime? _date(Map<String, Object?> row, String column) {
    final Object? value = row[column];
    if (value is! int) return null;
    return DateTime.fromMillisecondsSinceEpoch(value);
  }

  /// Reads a list of identifiers stored as a JSON array.
  static List<String> _strings(Map<String, Object?> row, String column) {
    final Object? raw = row[column];
    if (raw is! String || raw.isEmpty) return const <String>[];
    final Object? decoded = jsonDecode(raw);
    if (decoded is! List<Object?>) return const <String>[];
    return List<String>.unmodifiable(decoded.whereType<String>());
  }

  /// Reads a column holding an identifier.
  static Id<Tag>? _optionalId<Tag extends IdTag>(String value) {
    if (value.isEmpty) return null;
    return Id<Tag>(value);
  }

  /// Builds a list of typed identifiers.
  static List<Id<Tag>> _identifiers<Tag extends IdTag>(List<String> values) =>
      List<Id<Tag>>.unmodifiable(values.map(Id<Tag>.new));

  /// Reads a column holding an editorial stage.
  static ManuscriptStatus _statusOf(Map<String, Object?> row, String column) {
    final String name = _text(row, column);
    for (final ManuscriptStatus status in ManuscriptStatus.values) {
      if (status.name == name) return status;
    }
    return ManuscriptStatus.draft;
  }

  /// Converts a timestamp into the milliseconds stored by SQLite.
  static int? _milliseconds(DateTime? value) => value?.millisecondsSinceEpoch;

  /// Orders two rows by their order key.
  static int _byOrderKey(
    Map<String, Object?> left,
    Map<String, Object?> right,
  ) {
    final int byKey = _text(
      left,
      'order_key',
    ).compareTo(_text(right, 'order_key'));
    if (byKey != 0) return byKey;
    return _text(left, 'id').compareTo(_text(right, 'id'));
  }
}
