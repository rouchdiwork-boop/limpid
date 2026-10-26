-- Indicateurs de fonctionnalite du back-office (T10).
-- L'activation se fait a chaud : la ligne est lue a chaque appel et n'est
-- jamais mise en cache, donc aucun redemarrage du serveur n'est necessaire.
-- La ligne qui porte l'indicateur est aussi la trace de sa derniere
-- modification : l'administrateur qui l'a changee et l'instant du changement.
CREATE TABLE IF NOT EXISTS feature_flags (
  flag_key    TEXT PRIMARY KEY,
  is_enabled  BOOLEAN NOT NULL DEFAULT FALSE,
  description TEXT NOT NULL DEFAULT '',
  updated_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_by  TEXT NOT NULL DEFAULT ''
);
