-- La vente des livres : le prix, le droit de lecture et les codes promo
-- (B5, B6, B7).
--
-- Trois tables vivent dans cette migration.
--
-- `book_sales` porte le prix d'un livre : un livre se vend une fois, son
-- prix n'est donc pas une donnee de formule. La ligne est unique par livre
-- (`project_id` est la cle primaire) : un livre a un prix, pas deux. Les
-- parts sont comptees en milliemes : 9000 milliemes font 90 % pour
-- l'auteur, 1000 pour la plateforme. Elles sont configurables par compte,
-- et la regle par defaut est ecrite dans le service de partage.
--
-- `entitlements` porte le droit de lecture achete. La ligne est unique par
-- couple (acheteur, livre) et unique par commande : le meme paiement ne
-- cree jamais deux droits. La ventilation du montant partage vit sur la
-- meme ligne : elle est ecrite quand la commande est payee, jamais avant.
--
-- `promo_codes` porte la remise. La valeur est une pourcentage en
-- milliemes quand le type est `percent`, et un montant en centimes quand
-- le type est `amount`. `uses` compte les utilisations accordees et
-- `max_uses_per_account` borne l'usage par compte ; les usages elles-memes
-- sont comptes dans `promo_code_usages`, ce qui permet de decrementer le
-- quota d'un code de facon atomique et de refuser un code deja utilise.
--
-- Les horodatages sont des entiers : microsecondes depuis l'epoch Unix
-- (UTC), la convention du dialecte SQLite (voir `SqliteValues`).
CREATE TABLE IF NOT EXISTS book_sales (
  project_id     TEXT PRIMARY KEY,
  owner_id       TEXT NOT NULL,
  title          TEXT NOT NULL,
  price_cents    INTEGER NOT NULL,
  currency       TEXT NOT NULL,
  status         TEXT NOT NULL,
  author_share   INTEGER NOT NULL,
  platform_share INTEGER NOT NULL,
  artifact_key   TEXT,
  created_at     INTEGER NOT NULL,
  updated_at     INTEGER NOT NULL,
  published_at   INTEGER
);

CREATE INDEX IF NOT EXISTS book_sales_owner_idx
  ON book_sales (owner_id, updated_at DESC);

CREATE TABLE IF NOT EXISTS entitlements (
  id                    TEXT PRIMARY KEY,
  user_id               TEXT NOT NULL,
  project_id            TEXT NOT NULL,
  source                TEXT NOT NULL,
  granted_at            INTEGER NOT NULL,
  created_at            INTEGER NOT NULL,
  amount_cents          INTEGER NOT NULL DEFAULT 0,
  currency              TEXT NOT NULL DEFAULT 'eur',
  author_share          INTEGER NOT NULL DEFAULT 0,
  platform_share        INTEGER NOT NULL DEFAULT 0,
  author_amount_cents   INTEGER NOT NULL DEFAULT 0,
  platform_amount_cents INTEGER NOT NULL DEFAULT 0,
  promo_code            TEXT
);

CREATE UNIQUE INDEX IF NOT EXISTS entitlements_user_project_idx
  ON entitlements (user_id, project_id);

CREATE UNIQUE INDEX IF NOT EXISTS entitlements_source_idx
  ON entitlements (source);

CREATE INDEX IF NOT EXISTS entitlements_project_idx
  ON entitlements (project_id, granted_at DESC);

CREATE TABLE IF NOT EXISTS promo_codes (
  code                 TEXT PRIMARY KEY,
  discount_type        TEXT NOT NULL,
  value                INTEGER NOT NULL,
  currency             TEXT NOT NULL DEFAULT 'eur',
  max_uses             INTEGER NOT NULL,
  uses                 INTEGER NOT NULL DEFAULT 0,
  max_uses_per_account INTEGER NOT NULL DEFAULT 1,
  expires_at           INTEGER NOT NULL,
  created_at           INTEGER NOT NULL
);

CREATE INDEX IF NOT EXISTS promo_codes_expires_at_idx
  ON promo_codes (expires_at);

CREATE TABLE IF NOT EXISTS promo_code_usages (
  id      TEXT PRIMARY KEY,
  code    TEXT NOT NULL,
  user_id TEXT NOT NULL,
  used_at INTEGER NOT NULL
);

CREATE INDEX IF NOT EXISTS promo_code_usages_account_idx
  ON promo_code_usages (code, user_id);
