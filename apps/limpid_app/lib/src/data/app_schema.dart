/// The schema of the local database of the application.
///
/// The statements are plain SQL, executed once when the database is opened.
/// They are written by hand rather than generated: the layer must compile
/// without `build_runner`, which the monorepo forbids while several agents
/// work on the same package (D-27).
///
/// ## Where the CRDT documents live
///
/// The block trees of the scenes are **not** stored in these tables: they
/// live in the snapshot table of `limpid_sync`, written by
/// `DriftSnapshotStore`, which knows how to serialise a compacted operation
/// journal. The `document_index` table below is the routing index: it tells
/// which project a synchronised document belongs to, so the synchronisation
/// can address the right route of the API.
///
/// ## Where the discussions live
///
/// The `comment_threads` and `comments` tables hold the discussions of the
/// review. The **anchors** stay in the CRDT — they are marks added to the
/// blocks, and they never conflict with the text (D-16) — but the
/// conversation itself, its author and its resolution live here, so the
/// review survives the restart of the application.
///
/// ## Where the publication state lives
///
/// The table `projects` carries the **two** states of the publication (D-33):
/// `status` — the stage of the writing — and `is_public` — the visibility in
/// the showcase. The local table carries `is_public` like the table of the
/// server, so the synchroniser can transmit the intention to publish: a book
/// that is published on the device but not public on the server would never
/// reach the showcase.
library;

/// The DDL of the local database.
///
/// Every statement is idempotent: the schema is applied on every opening,
/// and the tables of the synchronisation package are created by Drift itself.
const List<String> localSchemaStatements = <String>[
  '''
CREATE TABLE IF NOT EXISTS projects (
  id TEXT PRIMARY KEY NOT NULL,
  owner_id TEXT NOT NULL,
  title TEXT NOT NULL,
  synopsis TEXT NOT NULL DEFAULT '',
  status TEXT NOT NULL,
  order_key TEXT NOT NULL,
  is_public INTEGER NOT NULL DEFAULT 0,
  series_ids TEXT NOT NULL DEFAULT '[]',
  chapter_ids TEXT NOT NULL DEFAULT '[]',
  created_at INTEGER,
  updated_at INTEGER
)''',
  'CREATE INDEX IF NOT EXISTS projects_updated_at ON projects (updated_at DESC)',
  '''
CREATE TABLE IF NOT EXISTS chapters (
  id TEXT PRIMARY KEY NOT NULL,
  project_id TEXT NOT NULL DEFAULT '',
  volume_id TEXT,
  title TEXT NOT NULL,
  synopsis TEXT NOT NULL DEFAULT '',
  status TEXT NOT NULL,
  order_key TEXT NOT NULL,
  scene_ids TEXT NOT NULL DEFAULT '[]',
  target_word_count INTEGER NOT NULL DEFAULT 0,
  created_at INTEGER,
  updated_at INTEGER
)''',
  'CREATE INDEX IF NOT EXISTS chapters_project ON chapters (project_id, order_key)',
  '''
CREATE TABLE IF NOT EXISTS scenes (
  id TEXT PRIMARY KEY NOT NULL,
  chapter_id TEXT NOT NULL,
  document_id TEXT NOT NULL,
  title TEXT NOT NULL,
  synopsis TEXT NOT NULL DEFAULT '',
  status TEXT NOT NULL,
  order_key TEXT NOT NULL,
  point_of_view TEXT,
  word_count INTEGER NOT NULL DEFAULT 0,
  target_word_count INTEGER NOT NULL DEFAULT 0,
  created_at INTEGER,
  updated_at INTEGER
)''',
  'CREATE INDEX IF NOT EXISTS scenes_chapter ON scenes (chapter_id, order_key)',
  '''
CREATE TABLE IF NOT EXISTS document_index (
  document_id TEXT PRIMARY KEY NOT NULL,
  scene_id TEXT NOT NULL,
  project_id TEXT NOT NULL,
  updated_at INTEGER NOT NULL DEFAULT 0
)''',
  'CREATE INDEX IF NOT EXISTS document_index_project ON document_index (project_id)',
  '''
CREATE TABLE IF NOT EXISTS sync_cursors (
  document_id TEXT PRIMARY KEY NOT NULL,
  lamport INTEGER NOT NULL DEFAULT 0
)''',
  '''
CREATE TABLE IF NOT EXISTS preferences (
  key TEXT PRIMARY KEY NOT NULL,
  value TEXT NOT NULL
)''',
  '''
CREATE TABLE IF NOT EXISTS comment_threads (
  id TEXT PRIMARY KEY NOT NULL,
  project_id TEXT NOT NULL,
  mark_id TEXT NOT NULL,
  excerpt TEXT NOT NULL DEFAULT '',
  is_resolved INTEGER NOT NULL DEFAULT 0,
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL,
  resolved_at INTEGER
)''',
  'CREATE INDEX IF NOT EXISTS comment_threads_project '
      'ON comment_threads (project_id, created_at ASC)',
  '''
CREATE TABLE IF NOT EXISTS comments (
  id TEXT PRIMARY KEY NOT NULL,
  thread_id TEXT NOT NULL,
  author_id TEXT NOT NULL,
  body TEXT NOT NULL,
  created_at INTEGER NOT NULL,
  edited_at INTEGER
)''',
  'CREATE INDEX IF NOT EXISTS comments_thread '
      'ON comments (thread_id, created_at ASC)',
];
