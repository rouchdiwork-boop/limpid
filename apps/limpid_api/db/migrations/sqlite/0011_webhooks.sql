-- Les cles d'API et les webhooks sortants (T9).
-- Une cle d'API n'est jamais stockee en clair : la table ne porte que son
-- empreinte, ce qui fait qu'une fuite de la base ne donne aucune cle
-- utilisable. La cle elle-meme est montree une seule fois, a la creation,
-- puis a chaque rotation.
-- Le secret de signature d'un point de rappel est lui stockee : le serveur
-- signe les livraisons sortantes, il lui faut donc la cle. Il n'est jamais
-- journalise et n'est renvoye qu'a la creation et a la rotation.
-- Les horodatages sont des entiers : microsecondes depuis l'epoch Unix (UTC),
-- et un booleen est un entier valant 0 ou 1.
CREATE TABLE IF NOT EXISTS api_keys (
  id           TEXT PRIMARY KEY,
  user_id      TEXT NOT NULL,
  name         TEXT NOT NULL,
  key_hash     TEXT NOT NULL,
  scopes       TEXT NOT NULL,
  is_active    INTEGER NOT NULL DEFAULT 1,
  created_at   INTEGER NOT NULL,
  rotated_at   INTEGER,
  revoked_at   INTEGER,
  last_used_at INTEGER
);

CREATE UNIQUE INDEX IF NOT EXISTS api_keys_hash_idx
  ON api_keys (key_hash);

CREATE INDEX IF NOT EXISTS api_keys_user_idx
  ON api_keys (user_id, created_at, id);

-- Les points de rappel du compte : une URL, les evenements abonnes et le
-- secret de signature. La rotation du secret conserve l'ancien pendant la
-- periode de transition, pour que le destinataire accepte les deux.
CREATE TABLE IF NOT EXISTS webhook_endpoints (
  id                      TEXT PRIMARY KEY,
  user_id                 TEXT NOT NULL,
  url                     TEXT NOT NULL,
  events                  TEXT NOT NULL,
  secret                  TEXT NOT NULL,
  previous_secret         TEXT,
  previous_secret_expires_at INTEGER,
  is_active               INTEGER NOT NULL DEFAULT 1,
  created_at              INTEGER NOT NULL,
  updated_at              INTEGER NOT NULL
);

CREATE INDEX IF NOT EXISTS webhook_endpoints_user_idx
  ON webhook_endpoints (user_id, created_at, id);

-- La preuve des livraisons : chaque tentative est consignee avec son statut,
-- le code HTTP repondu et l'instant. La charge est conservee pour que la
-- livraison puisse etre rejouee a la main.
CREATE TABLE IF NOT EXISTS webhook_deliveries (
  id            TEXT PRIMARY KEY,
  endpoint_id   TEXT NOT NULL,
  user_id       TEXT NOT NULL,
  event         TEXT NOT NULL,
  payload       TEXT NOT NULL,
  status        TEXT NOT NULL,
  http_status   INTEGER,
  error_message TEXT,
  attempts      INTEGER NOT NULL DEFAULT 0,
  created_at    INTEGER NOT NULL,
  completed_at  INTEGER
);

CREATE INDEX IF NOT EXISTS webhook_deliveries_user_idx
  ON webhook_deliveries (user_id, created_at, id);

CREATE INDEX IF NOT EXISTS webhook_deliveries_endpoint_idx
  ON webhook_deliveries (endpoint_id, created_at, id);
