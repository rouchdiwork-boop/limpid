-- Double authentification TOTP (D-19).
-- Le secret partage est propre au compte et n'est actif qu'apres la
-- confirmation d'un premier code : une inscription interrompue ne verrouille
-- jamais l'auteur hors de son propre compte.
-- Le secret n'est jamais journalise et n'est renvoye qu'a l'enrollement ;
-- les codes de recuperation ne sont stockes que sous forme d'empreinte et
-- ne servent qu'une fois.
CREATE TABLE IF NOT EXISTS two_factor (
  user_id    TEXT PRIMARY KEY,
  secret     TEXT NOT NULL,
  is_enabled BOOLEAN NOT NULL DEFAULT FALSE,
  created_at TIMESTAMPTZ NOT NULL,
  enabled_at TIMESTAMPTZ
);

CREATE TABLE IF NOT EXISTS two_factor_recovery_codes (
  user_id   TEXT NOT NULL,
  code_hash TEXT NOT NULL,
  used_at   TIMESTAMPTZ,
  PRIMARY KEY (user_id, code_hash)
);
