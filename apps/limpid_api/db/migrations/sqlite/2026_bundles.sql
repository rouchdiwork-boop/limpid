-- Le bundle : un ensemble de livres vendu comme un seul produit (B6).
--
-- `bundles` porte le bundle : son titre, sa description, les livres qu'il
-- contient et son prix. Le prix est **pose** : il ne se recalcule pas a
-- partir des prix des livres. La ligne est unique par bundle (`id` est la
-- cle primaire) : un bundle a un prix, pas deux.
--
-- `project_ids` porte la liste des livres du bundle, dans l'ordre. C'est un
-- document JSON : l'ordre fait partie du bundle, et la liste ordonnee est ce
-- que la colonne porte. Un bundle n'est pas multi-vendeurs : le compte qui
-- le vend (`owner_id`) est l'auteur de tous les livres qu'il contient, et
-- c'est lui qui encaisse la vente.
--
-- La colonne `bundle_id` des droits de lecture dit, pour chaque livre
-- achete, le bundle qui l'a porte. C'est elle qui permet a l'acheteur de
-- voir d'ou vient son livre : les livres achetés par un bundle montrent le
-- bundle dans leur provenance.
--
-- Les horodatages sont des entiers : microsecondes depuis l'epoch Unix
-- (UTC), la convention du dialecte SQLite (voir `SqliteValues`).
CREATE TABLE IF NOT EXISTS bundles (
  id           TEXT PRIMARY KEY,
  owner_id     TEXT NOT NULL,
  title        TEXT NOT NULL,
  description  TEXT NOT NULL DEFAULT '',
  project_ids  TEXT NOT NULL,
  price_cents  INTEGER NOT NULL,
  currency     TEXT NOT NULL DEFAULT 'eur',
  is_published INTEGER NOT NULL DEFAULT 0,
  created_at   INTEGER NOT NULL
);

CREATE INDEX IF NOT EXISTS bundles_owner_idx
  ON bundles (owner_id, created_at DESC);

ALTER TABLE entitlements ADD COLUMN bundle_id TEXT;
