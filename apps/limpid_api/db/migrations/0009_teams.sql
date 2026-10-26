-- Les equipes, leurs membres et leurs roles (D-16, T11).
-- L'equipe porte son propre role par membre : le role sur un projet reste
-- celui de `project_members`, les deux ne se confondent pas.
CREATE TABLE IF NOT EXISTS teams (
  id         TEXT PRIMARY KEY,
  name       TEXT NOT NULL,
  owner_id   TEXT NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS teams_owner_idx
  ON teams (owner_id);

CREATE TABLE IF NOT EXISTS team_members (
  team_id    TEXT NOT NULL REFERENCES teams (id) ON DELETE CASCADE,
  user_id    TEXT NOT NULL,
  role       TEXT NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (team_id, user_id)
);

CREATE INDEX IF NOT EXISTS team_members_user_idx
  ON team_members (user_id);

-- La trace des invitations : qui a invite qui, avec quel role et quand.
CREATE TABLE IF NOT EXISTS team_invitations (
  id         TEXT PRIMARY KEY,
  team_id    TEXT NOT NULL REFERENCES teams (id) ON DELETE CASCADE,
  user_id    TEXT NOT NULL,
  role       TEXT NOT NULL,
  invited_by TEXT NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS team_invitations_team_idx
  ON team_invitations (team_id, created_at, id);
