-- Les partages en lecture des livres (C5).
-- Un partage relie un livre, son proprietaire et un jeton secret. Le jeton
-- n'est jamais stocke en clair : la table ne porte que son empreinte, ce
-- qui fait qu'une fuite de la base ne donne aucun lien utilisable. Le jeton
-- est montre une seule fois, a la creation.
-- Un partage n'accorde aucun droit d'ecriture : il ouvre le document, rien
-- d'autre. La revocation et l'expiration ferment la porte.
-- Les horodatages sont des entiers : microsecondes depuis l'epoch Unix (UTC),
-- et un booleen est un entier valant 0 ou 1.
CREATE TABLE IF NOT EXISTS project_shares (
  id          TEXT PRIMARY KEY,
  project_id  TEXT NOT NULL,
  owner_id    TEXT NOT NULL,
  token_hash  TEXT NOT NULL,
  expires_at  INTEGER NOT NULL,
  is_revoked  INTEGER NOT NULL DEFAULT 0,
  created_at  INTEGER NOT NULL,
  revoked_at  INTEGER
);

CREATE UNIQUE INDEX IF NOT EXISTS project_shares_hash_idx
  ON project_shares (token_hash);

CREATE INDEX IF NOT EXISTS project_shares_owner_idx
  ON project_shares (owner_id, created_at DESC, id);

CREATE INDEX IF NOT EXISTS project_shares_project_idx
  ON project_shares (project_id);
