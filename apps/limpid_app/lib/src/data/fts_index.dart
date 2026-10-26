import 'package:drift/drift.dart';
import 'package:limpid_app/src/data/app_database.dart';
import 'package:limpid_app/src/domain/search_repository.dart';
import 'package:limpid_core/limpid_core.dart';
import 'package:limpid_sync/limpid_sync.dart';

/// The kind of a row of the index.
enum SearchRowKind {
  /// The row holds the title of a scene.
  ///
  /// The title of the project and the title of the scene are indexed
  /// together: a writer who looks for the name of a book finds its scenes.
  scene,

  /// The row holds the text of a block of a scene.
  block,
}

/// A row of the index, as the database holds it.
final class IndexedRow {
  /// Creates a row.
  const IndexedRow({
    required this.documentId,
    required this.sceneId,
    required this.projectId,
    required this.blockId,
    required this.kind,
    required this.sceneTitle,
    required this.projectTitle,
    required this.excerpt,
    required this.highlights,
    required this.relevance,
  });

  /// The identifier of the CRDT document the row belongs to.
  final String documentId;

  /// The identifier of the scene the row belongs to.
  final String sceneId;

  /// The identifier of the project the scene belongs to.
  final String projectId;

  /// The identifier of the block the row holds.
  ///
  /// It is empty for a row that holds the title of a scene.
  final String blockId;

  /// The kind of the row.
  final SearchRowKind kind;

  /// The title of the scene.
  final String sceneTitle;

  /// The title of the project.
  final String projectTitle;

  /// The passage found, with the words that surround it.
  final String excerpt;

  /// The places of the query found in [excerpt].
  final List<SearchHighlight> highlights;

  /// The relevance of the row: the higher, the closer to the query.
  final double relevance;
}

/// The full-text index of the manuscripts of the device.
///
/// ## The shape of the index
///
/// The index is a **virtual table** of FTS5, `documents_fts`. It holds one
/// row per block of a scene — the text of the block — and one row per scene
/// — the title of the project and the title of the scene.
///
/// The text of the blocks is the only indexed column. A single indexed column
/// keeps the relevance readable: the length of a row is the length of a
/// passage, and the rows that mention the words of the query the most often
/// come first. A trigger cannot feed this table: the text of the blocks
/// lives in the CRDT journal of the synchronisation, and only the data layer
/// can restore it. The index is therefore written by the data layer — see
/// [reconcile].
///
/// ## The index follows the source
///
/// An index that lags behind the manuscript is worse than no index at all:
/// it sends the writer to a passage that no longer exists. The index is
/// therefore a **projection** of the source, and it is brought back in line
/// with it before every search — see [reconcile].
///
/// The comparison is cheap: it reads the metadata of the documents, never
/// their text. Only the documents that really changed — a new version of the
/// CRDT journal, a new title of scene or of project — are read again.
final class FtsIndex {
  /// Creates an index on top of [database].
  FtsIndex(this._database);

  /// The local database holding the tables.
  final AppDatabase _database;

  /// The column of the virtual table that holds the indexed text.
  ///
  /// The text is the **first** column of the table: the marker FTS5 puts
  /// around a passage is read from it.
  static const int _bodyColumn = 0;

  /// The number of tokens the excerpt keeps around the passage.
  static const int _excerptTokens = 24;

  /// The separator between the title of the project and the title of the
  /// scene.
  ///
  /// It is indexed as a separator: it never becomes a word of the index.
  static const String _titleSeparator = ' — ';

  /// Brings the index of [accountId] in line with the source.
  ///
  /// The method is called before every search. It reads the metadata of the
  /// documents of the account, compares it with what the index holds, and
  /// reads again the documents that changed. The text of a document is never
  /// read when it did not move.
  Future<void> reconcile(String accountId) async {
    final List<_DocumentState> documents = await _documentsOf(accountId);
    final Map<String, _DocumentState> known = await _statesOf(accountId);

    final Set<String> present = <String>{
      for (final _DocumentState document in documents) document.documentId,
    };

    // The documents the author deleted leave the index.
    for (final String documentId in known.keys) {
      if (present.contains(documentId)) continue;
      await _forget(accountId, documentId);
    }

    // The documents that moved are read again.
    for (final _DocumentState document in documents) {
      final _DocumentState? state = known[document.documentId];
      if (state != null && state.isUpToDateWith(document)) continue;
      await _index(accountId, document);
    }
  }

  /// The rows of the index that carry the words of [match].
  ///
  /// The rows come back in the order of their relevance: the most relevant
  /// first. The relevance is the BM25 of FTS5, negated so that the higher it
  /// is, the closer the row is to the query.
  Future<List<IndexedRow>> rows({
    required String accountId,
    required String match,
    required int limit,
  }) async {
    final List<QueryRow> rows = await _database.sync
        .customSelect(
          '''
SELECT
  block_id,
  scene_id,
  document_id,
  project_id,
  kind,
  scene_title,
  project_title,
  snippet(documents_fts, $_bodyColumn, char(1), char(2), '…', $_excerptTokens)
    AS excerpt,
  bm25(documents_fts) AS score
FROM documents_fts
WHERE documents_fts MATCH ? AND account_id = ?
ORDER BY score ASC, document_id ASC, rowid ASC
LIMIT ?''',
          variables: <Variable<Object>>[
            Variable<String>(match),
            Variable<String>(accountId),
            Variable<int>(limit),
          ],
        )
        .get();
    return List<IndexedRow>.unmodifiable(rows.map(_rowOf));
  }

  /// The documents of the account, with the version of their content.
  ///
  /// The version of a document is the state of its CRDT journal: the moment
  /// of its last write and its highest Lamport timestamp. The journal is
  /// stored under the key of the account that owns it, and that key is the
  /// one the view of the snapshots builds.
  Future<List<_DocumentState>> _documentsOf(String accountId) async {
    final List<QueryRow> rows = await _database.sync
        .customSelect(
          '''
SELECT
  d.document_id AS document_id,
  d.scene_id AS scene_id,
  d.project_id AS project_id,
  COALESCE(s.title, '') AS scene_title,
  COALESCE(p.title, '') AS project_title,
  COALESCE(sn.updated_at, 0) AS snapshot_updated_at,
  COALESCE(sn.max_lamport, 0) AS snapshot_lamport
FROM document_index d
LEFT JOIN scenes s ON s.id = d.scene_id
LEFT JOIN projects p ON p.id = d.project_id
LEFT JOIN snapshot_rows sn
  ON sn.document_id = d.account_id || '/' || d.document_id
WHERE d.account_id = ?
ORDER BY d.document_id ASC''',
          variables: <Variable<Object>>[Variable<String>(accountId)],
        )
        .get();
    return List<_DocumentState>.unmodifiable(rows.map(_documentOf));
  }

  /// The state of the index for the documents of [accountId].
  Future<Map<String, _DocumentState>> _statesOf(String accountId) async {
    final List<QueryRow> rows = await _database.sync
        .customSelect(
          '''
SELECT
  document_id,
  scene_id,
  project_id,
  scene_title,
  project_title,
  snapshot_updated_at,
  snapshot_lamport
FROM search_index_state
WHERE account_id = ?''',
          variables: <Variable<Object>>[Variable<String>(accountId)],
        )
        .get();
    return <String, _DocumentState>{
      for (final QueryRow row in rows)
        _text(row, 'document_id'): _documentOf(row),
    };
  }

  /// Reads the document again and writes its rows in the index.
  ///
  /// The rows of the document are dropped first: a block that was deleted
  /// must not stay in the index.
  Future<void> _index(String accountId, _DocumentState document) async {
    final DocumentId identifier = DocumentId(document.documentId);
    final DocumentSnapshot? snapshot = await _database
        .snapshotsFor(() => accountId)
        .read(identifier);
    final CrdtDocument content =
        snapshot?.restore() ?? CrdtDocument.empty(identifier);

    await _database.sync.transaction(() async {
      await _forget(accountId, document.documentId);

      final String title = _titleOf(document);
      if (title.isNotEmpty) {
        await _insert(
          accountId: accountId,
          document: document,
          blockId: '',
          kind: SearchRowKind.scene,
          body: title,
        );
      }

      for (final Block block in content.blocks) {
        if (block.deleted) continue;
        final String text = block.content.plainText.trim();
        if (text.isEmpty) continue;
        await _insert(
          accountId: accountId,
          document: document,
          blockId: block.id.value,
          kind: SearchRowKind.block,
          body: text,
        );
      }

      await _remember(accountId, document);
    });
  }

  /// Writes a row in the index.
  Future<void> _insert({
    required String accountId,
    required _DocumentState document,
    required String blockId,
    required SearchRowKind kind,
    required String body,
  }) async {
    await _database.sync.customStatement(
      '''
INSERT INTO documents_fts (
  body,
  account_id,
  document_id,
  scene_id,
  project_id,
  block_id,
  kind,
  scene_title,
  project_title
) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)''',
      <Object?>[
        body,
        accountId,
        document.documentId,
        document.sceneId,
        document.projectId,
        blockId,
        kind.name,
        document.sceneTitle,
        document.projectTitle,
      ],
    );
  }

  /// Drops the rows and the state of a document.
  Future<void> _forget(String accountId, String documentId) async {
    await _database.sync.customStatement(
      'DELETE FROM documents_fts WHERE account_id = ? AND document_id = ?',
      <Object?>[accountId, documentId],
    );
    await _database.sync.customStatement(
      'DELETE FROM search_index_state '
      'WHERE account_id = ? AND document_id = ?',
      <Object?>[accountId, documentId],
    );
  }

  /// Records the state of a document in the index.
  Future<void> _remember(String accountId, _DocumentState document) async {
    await _database.sync.customStatement(
      '''
INSERT INTO search_index_state (
  account_id,
  document_id,
  scene_id,
  project_id,
  scene_title,
  project_title,
  snapshot_updated_at,
  snapshot_lamport
) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
ON CONFLICT(account_id, document_id) DO UPDATE SET
  scene_id = excluded.scene_id,
  project_id = excluded.project_id,
  scene_title = excluded.scene_title,
  project_title = excluded.project_title,
  snapshot_updated_at = excluded.snapshot_updated_at,
  snapshot_lamport = excluded.snapshot_lamport''',
      <Object?>[
        accountId,
        document.documentId,
        document.sceneId,
        document.projectId,
        document.sceneTitle,
        document.projectTitle,
        document.snapshotUpdatedAt,
        document.snapshotLamport,
      ],
    );
  }

  /// The text indexed for the title of a scene.
  String _titleOf(_DocumentState document) {
    final String scene = document.sceneTitle.trim();
    final String project = document.projectTitle.trim();
    if (scene.isEmpty) return project;
    if (project.isEmpty) return scene;
    return '$project$_titleSeparator$scene';
  }

  /// Reads a row of the index.
  IndexedRow _rowOf(QueryRow row) {
    final (String excerpt, List<SearchHighlight> highlights) = _excerptOf(
      _text(row, 'excerpt'),
    );
    return IndexedRow(
      documentId: _text(row, 'document_id'),
      sceneId: _text(row, 'scene_id'),
      projectId: _text(row, 'project_id'),
      blockId: _text(row, 'block_id'),
      kind: _kindOf(_text(row, 'kind')),
      sceneTitle: _text(row, 'scene_title'),
      projectTitle: _text(row, 'project_title'),
      excerpt: excerpt,
      highlights: highlights,
      // BM25 returns a negative number: the closer the row is to the query,
      // the more negative it is. The relevance is the opposite, so that the
      // higher it is, the better the row is.
      relevance: -_number(row, 'score'),
    );
  }

  /// Reads the state of a document from a row.
  _DocumentState _documentOf(QueryRow row) => _DocumentState(
    documentId: _text(row, 'document_id'),
    sceneId: _text(row, 'scene_id'),
    projectId: _text(row, 'project_id'),
    sceneTitle: _text(row, 'scene_title'),
    projectTitle: _text(row, 'project_title'),
    snapshotUpdatedAt: _integer(row, 'snapshot_updated_at'),
    snapshotLamport: _integer(row, 'snapshot_lamport'),
  );

  /// Reads the kind of a row of the index.
  SearchRowKind _kindOf(String value) => switch (value) {
    'block' => SearchRowKind.block,
    _ => SearchRowKind.scene,
  };

  /// Cuts the markers of FTS5 out of the excerpt.
  ///
  /// FTS5 surrounds every passage it found with the two markers given to
  /// `snippet()`. The markers are replaced by the bounds of the passage, so
  /// that the interface can paint it without parsing a markup.
  (String, List<SearchHighlight>) _excerptOf(String marked) {
    final StringBuffer plain = StringBuffer();
    final List<SearchHighlight> highlights = <SearchHighlight>[];
    int cursor = 0;
    while (true) {
      final int open = marked.indexOf(_openMarker, cursor);
      if (open < 0) break;
      final int close = marked.indexOf(_closeMarker, open + 1);
      if (close < 0) break;
      plain.write(marked.substring(cursor, open));
      plain.write(marked.substring(open + 1, close));
      highlights.add(
        SearchHighlight(
          start: plain.length - (close - open - 1),
          end: plain.length,
        ),
      );
      cursor = close + 1;
    }
    plain.write(marked.substring(cursor));
    return (plain.toString(), List<SearchHighlight>.unmodifiable(highlights));
  }

  /// The marker FTS5 puts before a passage.
  static const String _openMarker = '\u0001';

  /// The marker FTS5 puts after a passage.
  static const String _closeMarker = '\u0002';

  /// Reads a column of text, an empty string when it is missing.
  static String _text(QueryRow row, String column) {
    final Object? value = row.data[column];
    return value is String ? value : '';
  }

  /// Reads a column of integers, `0` when it is missing.
  static int _integer(QueryRow row, String column) {
    final Object? value = row.data[column];
    return value is int ? value : 0;
  }

  /// Reads a column of numbers, `0` when it is missing.
  static double _number(QueryRow row, String column) {
    final Object? value = row.data[column];
    return value is num ? value.toDouble() : 0;
  }
}

/// The state of a document, as the index knows it.
///
/// The state is compared with the state of the source to know whether the
/// index must read the document again.
final class _DocumentState {
  /// Creates a state.
  const _DocumentState({
    required this.documentId,
    required this.sceneId,
    required this.projectId,
    required this.sceneTitle,
    required this.projectTitle,
    required this.snapshotUpdatedAt,
    required this.snapshotLamport,
  });

  /// The identifier of the document.
  final String documentId;

  /// The identifier of the scene the document belongs to.
  final String sceneId;

  /// The identifier of the project the scene belongs to.
  final String projectId;

  /// The title of the scene, as it was indexed.
  final String sceneTitle;

  /// The title of the project, as it was indexed.
  final String projectTitle;

  /// The moment of the last write of the CRDT journal.
  final int snapshotUpdatedAt;

  /// The highest Lamport timestamp of the CRDT journal.
  final int snapshotLamport;

  /// Whether the index already holds this state of the document.
  bool isUpToDateWith(_DocumentState other) =>
      sceneId == other.sceneId &&
      projectId == other.projectId &&
      sceneTitle == other.sceneTitle &&
      projectTitle == other.projectTitle &&
      snapshotUpdatedAt == other.snapshotUpdatedAt &&
      snapshotLamport == other.snapshotLamport;
}
