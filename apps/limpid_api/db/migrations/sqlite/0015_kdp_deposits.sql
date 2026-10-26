-- Les depots de dossiers aupres d'Amazon KDP (T7).
-- La ligne est la trace d'une tentative de depot : l'identifiant du depot,
-- la publication preparee qui part, l'etat, l'identifiant du depot chez
-- Amazon, la liste des problemes releves et le motif d'un echec technique.
-- L'identifiant du depot est une cle locale : le contrat d'Amazon ne porte
-- pas de cle d'idempotence, c'est cette trace qui empeche le dossier de
-- partir deux fois.
-- Les colonnes JSON sont des `TEXT` qui portent le document encode, la
-- convention du dialecte SQLite.
-- Les horodatages sont des entiers : microsecondes depuis l'epoch Unix (UTC).
CREATE TABLE IF NOT EXISTS kdp_deposits (
  id                   TEXT PRIMARY KEY,
  publication_id       TEXT NOT NULL,
  user_id              TEXT NOT NULL,
  status               TEXT NOT NULL DEFAULT 'pending',
  amazon_submission_id TEXT,
  issues               TEXT NOT NULL DEFAULT '[]',
  failure_reason       TEXT,
  attempts             INTEGER NOT NULL DEFAULT 0,
  created_at           INTEGER NOT NULL,
  updated_at           INTEGER NOT NULL
);

CREATE INDEX IF NOT EXISTS kdp_deposits_user_idx
  ON kdp_deposits (user_id, created_at DESC, id);

CREATE UNIQUE INDEX IF NOT EXISTS kdp_deposits_publication_idx
  ON kdp_deposits (publication_id);
