-- Le consentement de l'auteur a l'envoi de son texte chez un tiers (D-08).
-- Une ligne par compte, par perimetre et par fournisseur : l'accord porte
-- sur ce que l'on autorise et sur celui a qui on l'autorise.
-- La ligne n'apparait qu'apres une decision de l'auteur : son absence
-- signifie qu'il n'a rien autorise.
-- La ligne ne porte aucun texte de l'auteur : une decision n'est pas une
-- matiere. Elle garde la date du dernier accord et celle du retrait, et le
-- journal d'audit garde toute l'histoire des decisions.
CREATE TABLE IF NOT EXISTS ai_consents (
  user_id    TEXT NOT NULL,
  scope      TEXT NOT NULL,
  provider   TEXT NOT NULL,
  is_granted BOOLEAN NOT NULL DEFAULT FALSE,
  granted_at TIMESTAMPTZ NOT NULL,
  revoked_at TIMESTAMPTZ,
  PRIMARY KEY (user_id, scope, provider)
);
