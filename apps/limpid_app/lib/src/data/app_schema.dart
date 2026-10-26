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
///
/// ## Where the hierarchy of the book lives
///
/// The manuscript is a tree of four levels below the project (D-02):
/// serie → tome → chapitre → scene. The relational tables of the
/// application carry it: `series`, `volumes`, `chapters` and `scenes`. Each
/// level keeps the ordered list of its children — `projects.series_ids`,
/// `series.volume_ids`, `volumes.chapter_ids`, `chapters.scene_ids` — and
/// the fractional index (`order_key`) that gives each child its place.
///
/// The scene is the only level that holds text: it owns one CRDT document.
/// The three levels above it are pure structure.
///
/// ## Where the search index lives
///
/// The table `documents_fts` is the **full-text index** of the manuscripts:
/// it holds one row per block of a scene — the text of the block — and one
/// row per scene — the title of the project and the title of the scene. It
/// is a virtual table of FTS5, and it is the only table of the database that
/// FTS5 owns.
///
/// The index is fed by the layer of the data, not by a trigger: the text of
/// the blocks lives in the CRDT journal of the synchronisation, and only the
/// code that restores that journal can read it. The table
/// `search_index_state` records what the index already holds for each
/// document, so that a search never reads a document that did not move.
///
/// ## The account of the rows
///
/// The local database is unique per device and outlives the session: two
/// accounts share the same file. The tables that carry the data of an
/// account — the preferences, the index of the documents and the cursors of
/// the synchronisation — therefore carry an `account_id` column, and their
/// primary key is composite: a row belongs to an account, never to the
/// device alone.
///
/// The manuscripts keep their own scope: the table `projects` is owned by
/// its author, and a book can be shared with a collaborator.
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
  // Les series : le premier niveau de la hierarchie du livre (D-02).
  // Un projet possede une liste ordonnee de series ; chaque serie porte
  // ses tomes. La colonne `project_id` est denormalisee comme celle des
  // chapitres : elle permet de retrouver le livre d'une serie sans
  // remonter la hierarchie entiere.
  '''
CREATE TABLE IF NOT EXISTS series (
  id TEXT PRIMARY KEY NOT NULL,
  project_id TEXT NOT NULL DEFAULT '',
  title TEXT NOT NULL,
  synopsis TEXT NOT NULL DEFAULT '',
  order_key TEXT NOT NULL,
  volume_ids TEXT NOT NULL DEFAULT '[]',
  created_at INTEGER,
  updated_at INTEGER
)''',
  'CREATE INDEX IF NOT EXISTS series_project ON series (project_id, order_key)',
  // Les tomes : le deuxieme niveau. Un tome appartient a une serie et
  // porte la liste ordonnee de ses chapitres.
  '''
CREATE TABLE IF NOT EXISTS volumes (
  id TEXT PRIMARY KEY NOT NULL,
  series_id TEXT NOT NULL DEFAULT '',
  project_id TEXT NOT NULL DEFAULT '',
  title TEXT NOT NULL,
  synopsis TEXT NOT NULL DEFAULT '',
  order_key TEXT NOT NULL,
  chapter_ids TEXT NOT NULL DEFAULT '[]',
  created_at INTEGER,
  updated_at INTEGER
)''',
  'CREATE INDEX IF NOT EXISTS volumes_series ON volumes (series_id, order_key)',
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
  account_id TEXT NOT NULL,
  document_id TEXT NOT NULL,
  scene_id TEXT NOT NULL,
  project_id TEXT NOT NULL,
  updated_at INTEGER NOT NULL DEFAULT 0,
  PRIMARY KEY (account_id, document_id)
)''',
  'CREATE INDEX IF NOT EXISTS document_index_project ON document_index (project_id)',
  '''
CREATE TABLE IF NOT EXISTS sync_cursors (
  account_id TEXT NOT NULL,
  document_id TEXT NOT NULL,
  lamport INTEGER NOT NULL DEFAULT 0,
  PRIMARY KEY (account_id, document_id)
)''',
  '''
CREATE TABLE IF NOT EXISTS preferences (
  account_id TEXT NOT NULL,
  key TEXT NOT NULL,
  value TEXT NOT NULL,
  PRIMARY KEY (account_id, key)
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
  // L'index de recherche plein texte. La table est virtuelle : elle est
  // écrite par la couche de donnees, jamais par un declencheur — le texte
  // des blocs vit dans le journal CRDT de la synchronisation, et seule la
  // couche de donnees sait le restaurer.
  '''
CREATE VIRTUAL TABLE IF NOT EXISTS documents_fts USING fts5(
  body,
  account_id UNINDEXED,
  document_id UNINDEXED,
  scene_id UNINDEXED,
  project_id UNINDEXED,
  block_id UNINDEXED,
  kind UNINDEXED,
  scene_title UNINDEXED,
  project_title UNINDEXED,
  tokenize = 'unicode61 remove_diacritics 2'
)''',
  // L'etat de l'index : il dit, pour chaque document, ce que l'index
  // contient deja. C'est lui qui permet de ne relire qu'un document qui a
  // bouge, et non tout le manuscrit.
  '''
CREATE TABLE IF NOT EXISTS search_index_state (
  account_id TEXT NOT NULL,
  document_id TEXT NOT NULL,
  scene_id TEXT NOT NULL DEFAULT '',
  project_id TEXT NOT NULL DEFAULT '',
  scene_title TEXT NOT NULL DEFAULT '',
  project_title TEXT NOT NULL DEFAULT '',
  snapshot_updated_at INTEGER NOT NULL DEFAULT 0,
  snapshot_lamport INTEGER NOT NULL DEFAULT 0,
  PRIMARY KEY (account_id, document_id)
)''',
];

/// The move of a database created before the account scope.
///
/// The tables that carry the data of an account gained an `account_id`
/// column, and their primary key became composite. SQLite cannot change a
/// primary key in place: the table is therefore renamed, rebuilt and filled
/// again.
///
/// The rows of the previous version belong to the author who was using the
/// device: they are kept, under the account of the session. A database that
/// was never partitioned keeps the preferences of its author.
final class AccountScopeMigration {
  /// Creates a migration.
  const AccountScopeMigration({
    required this.pragma,
    required this.rename,
    required this.create,
    required this.copy,
    required this.drop,
  });

  /// The statement that reads the columns of the table.
  ///
  /// The statement is a literal: SQLite does not accept a bound value in a
  /// `PRAGMA`.
  final String pragma;

  /// The statement that renames the table of the previous version.
  final String rename;

  /// The statement that creates the table of the new shape.
  final String create;

  /// The statement that copies the rows of the previous version.
  ///
  /// The statement holds one placeholder: the account of the session.
  final String copy;

  /// The statement that drops the table of the previous version.
  final String drop;
}

/// The migrations that give the tables of the local database their account.
const List<AccountScopeMigration> accountScopeMigrations =
    <AccountScopeMigration>[
      AccountScopeMigration(
        pragma: 'PRAGMA table_info(preferences)',
        rename: 'ALTER TABLE preferences RENAME TO preferences_legacy',
        create: '''
CREATE TABLE preferences (
  account_id TEXT NOT NULL,
  key TEXT NOT NULL,
  value TEXT NOT NULL,
  PRIMARY KEY (account_id, key)
)''',
        copy:
            'INSERT INTO preferences (account_id, key, value) '
            'SELECT ?, key, value FROM preferences_legacy',
        drop: 'DROP TABLE preferences_legacy',
      ),
      AccountScopeMigration(
        pragma: 'PRAGMA table_info(document_index)',
        rename: 'ALTER TABLE document_index RENAME TO document_index_legacy',
        create: '''
CREATE TABLE document_index (
  account_id TEXT NOT NULL,
  document_id TEXT NOT NULL,
  scene_id TEXT NOT NULL,
  project_id TEXT NOT NULL,
  updated_at INTEGER NOT NULL DEFAULT 0,
  PRIMARY KEY (account_id, document_id)
)''',
        copy:
            'INSERT INTO document_index (account_id, document_id, scene_id, '
            'project_id, updated_at) '
            'SELECT ?, document_id, scene_id, project_id, updated_at '
            'FROM document_index_legacy',
        drop: 'DROP TABLE document_index_legacy',
      ),
      AccountScopeMigration(
        pragma: 'PRAGMA table_info(sync_cursors)',
        rename: 'ALTER TABLE sync_cursors RENAME TO sync_cursors_legacy',
        create: '''
CREATE TABLE sync_cursors (
  account_id TEXT NOT NULL,
  document_id TEXT NOT NULL,
  lamport INTEGER NOT NULL DEFAULT 0,
  PRIMARY KEY (account_id, document_id)
)''',
        copy:
            'INSERT INTO sync_cursors (account_id, document_id, lamport) '
            'SELECT ?, document_id, lamport FROM sync_cursors_legacy',
        drop: 'DROP TABLE sync_cursors_legacy',
      ),
    ];
