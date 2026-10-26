-- L'unicite de la fiche Amazon KDP par projet (T8).
-- Un projet ne porte qu'une fiche : preparer deux fois le meme livre
-- rafraichit la fiche, il n'en cree pas une seconde. L'index unique est
-- la regle que la base applique, la mise a jour elle-meme vit dans le
-- service.
--
-- Les doublons que la preparation a deja produits sont effaces : la fiche
-- la plus recente est conservee, c'est celle que l'auteur relit. Les
-- fichiers qu'elle porte restent dans le stockage, ils sont remplaces a
-- la preparation suivante.
DELETE FROM kdp_publications
WHERE id NOT IN (
  SELECT id
  FROM (
    SELECT id,
           ROW_NUMBER() OVER (
             PARTITION BY project_id
             ORDER BY created_at DESC, id ASC
           ) AS position
    FROM kdp_publications
  ) AS ranked
  WHERE ranked.position = 1
);

CREATE UNIQUE INDEX IF NOT EXISTS kdp_publications_project_unique_idx
  ON kdp_publications (project_id);
