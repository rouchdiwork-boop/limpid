-- Les suppressions des tiers, dans le cadre de la purge RGPD (D-19).
-- La purge efface la donnee de l'API, puis celle des tiers : le compte dans
-- Supabase Auth et les artefacts dans le stockage objet. Un compte n'est
-- declare purge que lorsque les deux suppressions ont abouti ; une purge
-- incomplete laisse le compte marque comme a purger, et la passe suivante
-- reessaie.
--
-- `account_purge_deletions` porte l'etat d'une cible : l'authentification ou
-- le stockage objet. Une cible qui n'a pas de ligne n'a jamais ete tentee ;
-- une cible dont `deleted_at` est vide attend encore son erasure.
CREATE TABLE IF NOT EXISTS account_purge_deletions (
  user_id       TEXT NOT NULL,
  target        TEXT NOT NULL,
  deleted_at    TIMESTAMPTZ,
  deleted_count INTEGER NOT NULL DEFAULT 0,
  attempts      INTEGER NOT NULL DEFAULT 0,
  last_error    TEXT NOT NULL DEFAULT '',
  updated_at    TIMESTAMPTZ NOT NULL,
  PRIMARY KEY (user_id, target)
);

-- Les prefixes du stockage qui portent les artefacts du compte.
-- La ligne est ecrite AVANT l'effacement des donnees de l'API : les projets
-- qui portent ces prefixes disparaissent avec l'effacement, et la passe
-- suivante n'aurait plus aucun moyen de retrouver les artefacts.
CREATE TABLE IF NOT EXISTS account_purge_artifacts (
  user_id       TEXT NOT NULL,
  prefix        TEXT NOT NULL,
  deleted_at    TIMESTAMPTZ,
  deleted_count INTEGER NOT NULL DEFAULT 0,
  created_at    TIMESTAMPTZ NOT NULL,
  PRIMARY KEY (user_id, prefix)
);
