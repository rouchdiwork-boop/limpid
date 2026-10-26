-- Double authentification TOTP (D-19).
-- Le secret partage est propre au compte et n'est actif qu'apres la
-- confirmation d'un premier code : une inscription interrompue ne verrouille
-- jamais l'auteur hors de son propre compte.
-- Le secret n'est jamais journalise et n'est renvoye qu'a l'enrollement ;
-- les codes de recuperation ne sont stockes que sous forme d'empreinte et
-- ne servent qu'une fois.
-- Les horodatages sont des entiers : microsecondes depuis l'epoch Unix (UTC),
-- et un booleen est un entier valant 0 ou 1.
CREATE TABLE IF NOT EXISTS two_factor (
  user_id    TEXT PRIMARY KEY,
  secret     TEXT NOT NULL,
  is_enabled INTEGER NOT NULL DEFAULT 0,
  created_at INTEGER NOT NULL,
  enabled_at INTEGER
);

CREATE TABLE IF NOT EXISTS two_factor_recovery_codes (
  user_id   TEXT NOT NULL,
  code_hash TEXT NOT NULL,
  used_at   INTEGER,
  PRIMARY KEY (user_id, code_hash)
);
