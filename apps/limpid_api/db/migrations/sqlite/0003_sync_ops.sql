-- Journal des operations CRDT, append-only.
-- La contrainte d'unicite porte l'idempotence structurelle (ARCHITECTURE.md §5.3).
CREATE TABLE IF NOT EXISTS sync_ops (
  id              TEXT PRIMARY KEY,
  project_id      TEXT NOT NULL REFERENCES projects (id) ON DELETE CASCADE,
  doc_id          TEXT NOT NULL,
  lamport         INTEGER NOT NULL,
  author_id       TEXT NOT NULL,
  type            TEXT NOT NULL,
  payload         TEXT NOT NULL DEFAULT '{}',
  schema_version  INTEGER NOT NULL DEFAULT 1,
  created_at      INTEGER NOT NULL,
  CONSTRAINT sync_ops_identity UNIQUE (doc_id, lamport, author_id)
);

CREATE INDEX IF NOT EXISTS sync_ops_project_lamport_idx
  ON sync_ops (project_id, lamport, author_id);
