-- L'invitation d'equipe devient un objet (D-16, critere 3.8).
-- L'invitation par courriel attend une reponse : elle porte une adresse, un
-- jeton, une date d'expiration et un etat. Le jeton n'est jamais stocke en
-- clair : la table ne porte que son empreinte, ce qui fait qu'une fuite de la
-- base ne donne aucun lien utilisable. Le jeton est montre une seule fois, a
-- la creation.
-- Le membre n'entre dans l'equipe qu'a l'acceptation : une invitation qui
-- expire est une invitation qui attend.
-- La table portait deja la trace des invitations immediates, qui vise un
-- compte existant et ajoute le membre sur-le-champ. Les deux cohabitent :
-- `user_id` porte le compte invite quand il est connu, `email` porte
-- l'adresse invitée, et `status` dit dans quel etat l'invitation est.
-- La colonne `status` vaut `accepted` par defaut : une invitation immediate
-- est acceptee par nature.
ALTER TABLE team_invitations RENAME TO team_invitations_trace;

CREATE TABLE IF NOT EXISTS team_invitations (
  id          TEXT PRIMARY KEY,
  team_id     TEXT NOT NULL REFERENCES teams (id) ON DELETE CASCADE,
  user_id     TEXT,
  email       TEXT,
  role        TEXT NOT NULL,
  token_hash  TEXT,
  status      TEXT NOT NULL DEFAULT 'accepted',
  invited_by  TEXT NOT NULL,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
  expires_at  TIMESTAMPTZ,
  accepted_at TIMESTAMPTZ,
  accepted_by TEXT
);

INSERT INTO team_invitations
  (id, team_id, user_id, role, invited_by, created_at, status, accepted_at, accepted_by)
SELECT
  id, team_id, user_id, role, invited_by, created_at, 'accepted', created_at, user_id
FROM team_invitations_trace;

DROP TABLE team_invitations_trace;

CREATE INDEX IF NOT EXISTS team_invitations_team_idx
  ON team_invitations (team_id, created_at, id);

-- L'empreinte du jeton est unique : deux invitations ne portent jamais le
-- meme jeton. Les invitations immediates n'en portent pas.
CREATE UNIQUE INDEX IF NOT EXISTS team_invitations_token_idx
  ON team_invitations (token_hash);

CREATE INDEX IF NOT EXISTS team_invitations_email_idx
  ON team_invitations (team_id, email, status);
