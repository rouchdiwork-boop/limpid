-- Projets : racine du manuscrit, propriete et metadonnees editoriales.
-- Les horodatages sont des entiers : microsecondes depuis l'epoch Unix (UTC).
CREATE TABLE IF NOT EXISTS projects (
  id          TEXT PRIMARY KEY,
  owner_id    TEXT NOT NULL,
  title       TEXT NOT NULL,
  synopsis    TEXT NOT NULL DEFAULT '',
  status      TEXT NOT NULL DEFAULT 'draft',
  language    TEXT NOT NULL DEFAULT 'fr-FR',
  order_key   TEXT NOT NULL DEFAULT '5',
  is_public   INTEGER NOT NULL DEFAULT 0,
  created_at  INTEGER NOT NULL,
  updated_at  INTEGER NOT NULL,
  deleted_at  INTEGER
);

CREATE INDEX IF NOT EXISTS projects_owner_updated_idx
  ON projects (owner_id, updated_at DESC, id);

CREATE INDEX IF NOT EXISTS projects_updated_idx
  ON projects (updated_at DESC, id);
