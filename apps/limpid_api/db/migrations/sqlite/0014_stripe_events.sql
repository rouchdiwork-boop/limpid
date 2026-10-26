-- Les evenements Stripe traites (D-37).
-- La ligne est la cle d'idempotence du webhook Stripe : l'identifiant de
-- l'evenement Stripe en est la cle primaire, et son absence signifie que
-- l'evenement n'a jamais ete traite. Stripe renvoie le meme evenement
-- plusieurs fois : l'effet doit etre applique une seule fois.
-- La ligne ne porte que l'identifiant, le type et l'horodatage du
-- traitement : elle ne garde aucune donnee de paiement.
-- Les horodatages sont des entiers : microsecondes depuis l'epoch Unix (UTC).
CREATE TABLE IF NOT EXISTS stripe_events (
  event_id     TEXT PRIMARY KEY,
  event_type   TEXT NOT NULL,
  processed_at INTEGER NOT NULL
);

CREATE INDEX IF NOT EXISTS stripe_events_processed_at_idx
  ON stripe_events (processed_at);
