-- Le consentement de l'auteur a l'envoi de son texte chez un tiers (D-08).
-- Une ligne par compte, par perimetre et par fournisseur : l'accord porte
-- sur ce que l'on autorise et sur celui a qui on l'autorise.
-- La ligne n'apparait qu'apres une decision de l'auteur : son absence
-- signifie qu'il n'a rien autorise.
-- La ligne ne porte aucun texte de l'auteur : une decision n'est pas une
-- matiere. Elle garde la date du dernier accord et celle du retrait, et le
-- journal d'audit garde toute l'histoire des decisions.
-- Les horodatages sont des entiers : microsecondes depuis l'epoch Unix (UTC),
-- et un booleen est un entier valant 0 ou 1.
CREATE TABLE IF NOT EXISTS ai_consents (
  user_id    TEXT NOT NULL,
  scope      TEXT NOT NULL,
  provider   TEXT NOT NULL,
  is_granted INTEGER NOT NULL DEFAULT 0,
  granted_at INTEGER NOT NULL,
  revoked_at INTEGER,
  PRIMARY KEY (user_id, scope, provider)
);
