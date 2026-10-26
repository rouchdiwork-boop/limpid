## Contexte

<!-- Que change cette pull request ? Quel problème résout-elle ? -->

## Lot

<!--
Quel lot de la feuille de route cette pull request fait-elle avancer ?
Voir docs/ROADMAP.md (lots 0 à 7) et docs/FEATURE_MATRIX.md.
-->

- [ ] Lot 0 — Monorepo, CI, design system, authentification
- [ ] Lot 1 — Structure de projet, éditeur par blocs, sauvegarde locale
- [ ] Lot 2 — CRDT et transport de synchronisation
- [ ] Lot 3 — Révision, commentaires, présence, rôles
- [ ] Lot 4 — IA
- [ ] Lot 5 — Exports
- [ ] Lot 6 — Vitrine publique, Stripe, KDP
- [ ] Lot 7 — Plans, quotas, administration, 2FA, RGPD

## Décisions

<!--
Une décision d'architecture nouvelle ? Elle doit être écrite dans
docs/DECISIONS.md (D-01 et suivantes), datée et contraignante.
-->

- [ ] Aucune décision d'architecture nouvelle
- [ ] Décision ajoutée dans `docs/DECISIONS.md` (préciser le numéro : D-__)

## Definition of Done

<!--
Se cocher uniquement si chaque point est vérifié. La CI échoue sur le
premier point non respecté.
-->

- [ ] `flutter analyze` : 0 erreur, 0 avertissement
- [ ] `dart format --set-exit-if-changed .` : propre
- [ ] Tests verts (unitaires, widgets, fuzz de synchronisation)
- [ ] Aucun `TODO` ou `FIXME` non justifié
- [ ] Fonctionnement hors-ligne vérifié pour le périmètre annoncé
- [ ] Écrans valides dans les quatre thèmes
- [ ] Navigation clavier et lecteur d'écran vérifiés
- [ ] Textes internationalisés, aucune chaîne en dur
- [ ] Documentation à jour dans `docs/`

## Sécurité

- [ ] Aucun secret dans le dépôt
- [ ] Entrées utilisateur validées
- [ ] Requêtes SQL paramétrées
- [ ] Aucun secret personnel dans les logs

## Vérification

<!--
Comment la pull request a-t-elle été vérifiée ? Quelles commandes ont été
lancées, et quel résultat ?
-->

```bash
bash tool/check.sh
```

<!-- Captures, journaux, mesures de performance utile. -->

## Points d'attention pour la relecture

<!--
Qu'est-ce qui mérite une attention particulière ? Zones risquées, choix
douteux, dette assumée.
-->
