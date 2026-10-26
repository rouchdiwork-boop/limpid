-- Indicateurs de fonctionnalite du back-office (T10).
-- L'activation se fait a chaud : la ligne est lue a chaque appel et n'est
-- jamais mise en cache, donc aucun redemarrage du serveur n'est necessaire.
-- La ligne qui porte l'indicateur est aussi la trace de sa derniere
-- modification : l'administrateur qui l'a changee et l'instant du changement.
-- Les horodatages sont des entiers : microsecondes depuis l'epoch Unix (UTC).
CREATE TABLE IF NOT EXISTS feature_flags (
  flag_key    TEXT PRIMARY KEY,
  is_enabled  INTEGER NOT NULL DEFAULT 0,
  description TEXT NOT NULL DEFAULT '',
  updated_at  INTEGER NOT NULL,
  updated_by  TEXT NOT NULL DEFAULT ''
);
