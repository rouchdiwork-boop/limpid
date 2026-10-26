-- L'unicite de l'ISBN (T8).
--
-- Un ISBN designe un ouvrage imprime : deux fiches Amazon KDP ne peuvent
-- pas le porter. Le service refuse deja l'ISBN deja pris, mais son controle
-- et son ecriture sont deux moments distincts : deux preparations
-- concurrentes de deux livres differents pouraient passer entre les deux.
-- L'index unique ferme la fenetre — c'est la base qui tranche.
--
-- Les doublons deja produits sont effaces : la fiche la plus recente est
-- conservee, c'est celle que l'auteur relit. Les fichiers qu'elle porte
-- restent dans le stockage, ils sont remplaces a la preparation suivante.
DELETE FROM kdp_publications
WHERE isbn IS NOT NULL
  AND isbn <> ''
  AND id NOT IN (
    SELECT id
    FROM (
      SELECT id,
             ROW_NUMBER() OVER (
               PARTITION BY isbn
               ORDER BY created_at DESC, id ASC
             ) AS position
      FROM kdp_publications
      WHERE isbn IS NOT NULL AND isbn <> ''
    ) AS ranked
    WHERE ranked.position = 1
  );

-- L'index est partiel : une fiche sans ISBN (le cas ordinaire, avant que
-- l'auteur en saisisse un) ne peut pas alleigner la regle.
CREATE UNIQUE INDEX IF NOT EXISTS kdp_publications_isbn_unique_idx
  ON kdp_publications (isbn)
  WHERE isbn IS NOT NULL AND isbn <> '';
