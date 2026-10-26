-- La hierarchie du livre : serie, tome, chapitre, scene (D-02).
--
-- La scene reste l'unite atomique de synchronisation : son texte vit dans
-- le journal CRDT (`sync_ops`), et cette table n'en porte que la
-- structure — son titre, sa place dans son chapitre et son volume de
-- mots. Les trois niveaux au-dessus ne portent aucun texte : ils sont la
-- structure du livre.
--
-- Chaque table porte le projet qui la contient : la colonne est
-- denormalisee, comme celle des chapitres du peripherique, pour que la
-- purge et les lectures de la bibliotheque trouvent le livre d'un element
-- sans remonter toute la hierarchie.
CREATE TABLE IF NOT EXISTS series (
  id          TEXT PRIMARY KEY,
  project_id  TEXT NOT NULL REFERENCES projects (id) ON DELETE CASCADE,
  title       TEXT NOT NULL,
  synopsis    TEXT NOT NULL DEFAULT '',
  order_key   TEXT NOT NULL DEFAULT '5',
  volume_ids  TEXT NOT NULL DEFAULT '[]',
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS series_project_idx
  ON series (project_id, order_key);

CREATE TABLE IF NOT EXISTS volumes (
  id          TEXT PRIMARY KEY,
  project_id  TEXT NOT NULL REFERENCES projects (id) ON DELETE CASCADE,
  series_id   TEXT REFERENCES series (id) ON DELETE CASCADE,
  title       TEXT NOT NULL,
  synopsis    TEXT NOT NULL DEFAULT '',
  order_key   TEXT NOT NULL DEFAULT '5',
  chapter_ids TEXT NOT NULL DEFAULT '[]',
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS volumes_series_idx
  ON volumes (series_id, order_key);

CREATE TABLE IF NOT EXISTS chapters (
  id                TEXT PRIMARY KEY,
  project_id        TEXT NOT NULL REFERENCES projects (id) ON DELETE CASCADE,
  volume_id         TEXT REFERENCES volumes (id) ON DELETE CASCADE,
  title             TEXT NOT NULL,
  synopsis          TEXT NOT NULL DEFAULT '',
  status            TEXT NOT NULL DEFAULT 'draft',
  order_key         TEXT NOT NULL DEFAULT '5',
  scene_ids         TEXT NOT NULL DEFAULT '[]',
  target_word_count INTEGER NOT NULL DEFAULT 0,
  created_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at        TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS chapters_project_idx
  ON chapters (project_id, order_key);

CREATE TABLE IF NOT EXISTS scenes (
  id                TEXT PRIMARY KEY,
  project_id        TEXT NOT NULL REFERENCES projects (id) ON DELETE CASCADE,
  chapter_id        TEXT NOT NULL REFERENCES chapters (id) ON DELETE CASCADE,
  document_id       TEXT NOT NULL,
  title             TEXT NOT NULL,
  synopsis          TEXT NOT NULL DEFAULT '',
  status            TEXT NOT NULL DEFAULT 'draft',
  order_key         TEXT NOT NULL DEFAULT '5',
  point_of_view     TEXT,
  word_count        INTEGER NOT NULL DEFAULT 0,
  target_word_count INTEGER NOT NULL DEFAULT 0,
  created_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at        TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS scenes_chapter_idx
  ON scenes (chapter_id, order_key);
