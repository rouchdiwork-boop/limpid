-- Les travaux d'export : l'export d'un livre est un travail, pas une requete.
--
-- Un livre de 80 000 mots tient une requete HTTP ouverte pendant des
-- dizaines de secondes : le proxy la coupe, et l'export est perdu apres
-- avoir facture. La table des travaux rend l'export asynchrone : la route
-- cree le travail et repond aussitot, le worker le produit.
--
-- Un travail est un **evenement**, pas un objet qu'on rejoue : une relance
-- cree un travail **neuf**, jamais elle ne ressuscite l'ancien. La ligne
-- garde donc la trace de ce qui s'est passe, et une ligne en echec garde
-- son message.
--
-- `format` porte le format demande et `cover` la variante de couverture :
-- le travail doit reproduire exactement la demande de l'auteur, sans quoi
-- l'artefact produit ne serait pas celui qu'il attendait.
--
-- `expires_at` vaut quinze minutes apres la fin du travail : l'artefact
-- produit disparait a cette heure, et l'adresse qui le sert refuse
-- ensuite de le rendre.
CREATE TABLE IF NOT EXISTS exports (
  id           TEXT PRIMARY KEY,
  user_id      TEXT NOT NULL,
  project_id   TEXT NOT NULL,
  format       TEXT NOT NULL,
  cover        TEXT NOT NULL DEFAULT 'front',
  status       TEXT NOT NULL,
  artifact_key TEXT,
  error        TEXT,
  error_code   TEXT,
  created_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
  started_at   TIMESTAMPTZ,
  finished_at  TIMESTAMPTZ,
  expires_at   TIMESTAMPTZ
);

-- Les travaux d'un compte, les plus recents d'abord : c'est la liste que
-- l'auteur suit.
CREATE INDEX IF NOT EXISTS exports_user_idx
  ON exports (user_id, created_at DESC);

-- La file du worker : les travaux en attente, les plus anciens d'abord.
CREATE INDEX IF NOT EXISTS exports_queue_idx
  ON exports (status, created_at ASC);

-- Les artefacts a effacer : le worker cherche les travaux termines dont
-- l'artefact a expire.
CREATE INDEX IF NOT EXISTS exports_expiry_idx
  ON exports (expires_at);
