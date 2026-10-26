-- Projets : racine du manuscrit, propriete et metadonnees editoriales.
CREATE TABLE IF NOT EXISTS projects (
  id          TEXT PRIMARY KEY,
  owner_id    TEXT NOT NULL,
  title       TEXT NOT NULL,
  synopsis    TEXT NOT NULL DEFAULT '',
  status      TEXT NOT NULL DEFAULT 'draft',
  language    TEXT NOT NULL DEFAULT 'fr-FR',
  order_key   TEXT NOT NULL DEFAULT '5',
  is_public   BOOLEAN NOT NULL DEFAULT FALSE,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
  deleted_at  TIMESTAMPTZ
);

CREATE INDEX IF NOT EXISTS projects_owner_updated_idx
  ON projects (owner_id, updated_at DESC, id);

CREATE INDEX IF NOT EXISTS projects_updated_idx
  ON projects (updated_at DESC, id);
