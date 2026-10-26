-- Formules des comptes et compteurs de consommation (D-15).
-- La formule affectee au compte est la source de verite du service de quota ;
-- les compteurs portent la consommation, par fonctionnalite et par periode.
-- La date de fin d'essai n'est renseignee que pendant l'essai gratuit de la
-- formule Ecrivain : au-dela, la formule effective redevient « Gratuit ».
CREATE TABLE IF NOT EXISTS account_plans (
  user_id           TEXT PRIMARY KEY,
  plan              TEXT NOT NULL,
  billing_period    TEXT NOT NULL DEFAULT 'monthly',
  trial_ends_at     TIMESTAMPTZ,
  trial_consumed_at TIMESTAMPTZ,
  period_started_at TIMESTAMPTZ NOT NULL,
  period_ends_at    TIMESTAMPTZ
);

CREATE TABLE IF NOT EXISTS quota_usage (
  user_id    TEXT NOT NULL,
  feature    TEXT NOT NULL,
  period_key TEXT NOT NULL,
  quantity   INTEGER NOT NULL DEFAULT 0,
  PRIMARY KEY (user_id, feature, period_key)
);

CREATE INDEX IF NOT EXISTS quota_usage_period_idx
  ON quota_usage (period_key);
