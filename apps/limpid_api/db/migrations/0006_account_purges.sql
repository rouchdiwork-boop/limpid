-- Purges definitives des comptes (D-19).
-- La demande de suppression vit dans le journal d'audit, qui en est la
-- source de verite : cette table garde la trace operationnelle de la purge.
-- La ligne est posee dans la meme transaction que l'effacement des donnees ;
-- elle sert de verrou d'exclusion mutuelle entre deux workers et rend la
-- purge idempotente.
CREATE TABLE IF NOT EXISTS account_purges (
  user_id       TEXT PRIMARY KEY,
  requested_at  TIMESTAMPTZ NOT NULL,
  scheduled_for TIMESTAMPTZ NOT NULL,
  purged_at     TIMESTAMPTZ NOT NULL,
  purged_by     TEXT NOT NULL
);

CREATE INDEX IF NOT EXISTS account_purges_purged_at_idx
  ON account_purges (purged_at);
