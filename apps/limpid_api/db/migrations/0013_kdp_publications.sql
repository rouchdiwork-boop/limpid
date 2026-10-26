-- Les publications Amazon KDP preparees (T6).
-- La ligne est la trace de ce qui a ete prepare : le livre, la version du
-- manuscrit, les metadonnees, l'horodatage et le resultat du controle de
-- soumission. Elle ne porte pas les liens de telechargement : ils sont
-- signes et expirent, la trace survit a leur expiration.
-- Les colonnes JSON portent les listes de la fiche produit et la liste des
-- problemes releves par le controle.
CREATE TABLE IF NOT EXISTS kdp_publications (
  id                 TEXT PRIMARY KEY,
  project_id         TEXT NOT NULL,
  user_id            TEXT NOT NULL,
  title              TEXT NOT NULL,
  author             TEXT NOT NULL,
  description        TEXT NOT NULL DEFAULT '',
  keywords           JSONB NOT NULL DEFAULT '[]'::jsonb,
  categories         JSONB NOT NULL DEFAULT '[]'::jsonb,
  issues             JSONB NOT NULL DEFAULT '[]'::jsonb,
  isbn               TEXT,
  language           TEXT NOT NULL DEFAULT 'fr-FR',
  publisher          TEXT,
  status             TEXT NOT NULL DEFAULT 'blocked',
  word_count         INTEGER NOT NULL DEFAULT 0,
  page_count         INTEGER NOT NULL DEFAULT 0,
  epub_key           TEXT NOT NULL,
  pdf_key            TEXT NOT NULL,
  epub_bytes         INTEGER NOT NULL DEFAULT 0,
  pdf_bytes          INTEGER NOT NULL DEFAULT 0,
  manuscript_version TEXT NOT NULL,
  created_at         TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS kdp_publications_project_idx
  ON kdp_publications (project_id, created_at DESC, id);

CREATE INDEX IF NOT EXISTS kdp_publications_user_idx
  ON kdp_publications (user_id, created_at DESC, id);
