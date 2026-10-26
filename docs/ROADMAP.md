# Limpid — Feuille de route

> Document normatif. Il découpe la v1 en 8 lots livrables, dans l'ordre défini
> par PROMPT §15, et décrit pour chaque lot l'objectif, le périmètre
> fonctionnel, les dépendances, les critères d'acceptation vérifiables, les
> risques et parades, la charge estimée et le plan de test.
>
> Le périmètre fonctionnel vient de [`FEATURE_MATRIX.md`](./FEATURE_MATRIX.md) :
> les fonctions v1, référencées par leurs identifiants (E, O, P, A, C, B, T).
> L'architecture est décrite dans [`ARCHITECTURE.md`](./ARCHITECTURE.md). Les
> décisions figées sont dans [`DECISIONS.md`](./DECISIONS.md) et le cahier des
> charges dans [`PROMPT.md`](./PROMPT.md).

**Version** : 1.0 — 2026-10-25 — **Statut** : normative

## Sommaire

| # | Section | Contenu |
|---|---|---|
| 1 | [Principes de découpage](#1-principes-de-découpage) | Règles de livraison |
| 2 | [Vue d'ensemble des lots](#2-vue-densemble-des-lots) | Ordre, charge, dépendances |
| 3 | [Lot 0 — Socle](#3-lot-0--socle) | Monorepo, CI, design system, authentification |
| 4 | [Lot 1 — Structure et éditeur](#4-lot-1--structure-narrative-et-éditeur) | Hiérarchie, blocs, sauvegarde locale |
| 5 | [Lot 2 — Synchronisation](#5-lot-2--synchronisation) | CRDT, transport, multi-appareils |
| 6 | [Lot 3 — Révision et collaboration](#6-lot-3--révision-et-collaboration) | Commentaires, présence, rôles |
| 7 | [Lot 4 — IA](#7-lot-4--ia) | Inline, plan, RAG, cohérence |
| 8 | [Lot 5 — Exports et couverture](#8-lot-5--exports-et-couverture) | EPUB, PDF, DOCX, couverture IA |
| 9 | [Lot 6 — Publication et vente](#9-lot-6--vitrine-stripe-et-kdp) | Vitrine, paiement, distribution |
| 10 | [Lot 7 — Plans, quotas, administration et RGPD](#10-lot-7--plans-quotas-administration-et-rgpd) | Plans, quotas, admin, RGPD |
| 11 | [Registre de risques](#11-registre-de-risques) | Risques globaux et parades |
| 12 | [Hors périmètre v1](#12-hors-périmètre-v1) | Exclusions assumées |
| 13 | [Plan de test par lot](#13-plan-de-test-par-lot) | Niveaux de test et seuils |

## 1. Principes de découpage

| Règle | Contenu |
|---|---|
| Ordre | Les 8 lots suivent l'ordre de livraison de PROMPT §15. Aucun lot ne commence avant que le précédent ne soit mergé. |
| Atomicité | Un lot est mergé seulement si `flutter analyze` est propre, les tests sont verts et la fonctionnalité est démontrable (PROMPT §13). |
| Tests | Toute fonctionnalité est livrée avec ses tests. Une PR sans test est incomplète (PROMPT §12). |
| Couverture | Les fonctions v1 de FEATURE_MATRIX sont couvertes. La table du §2 fait foi. |
| Charge | Échelle Fibonacci : 1 trivial, 2 petit, 3 moyen, 5 grand, 8 très grand, 13 épique. La charge d'un lot est la somme de ses postes ; elle est estimée, non planifiée. |
| Contenu livré | Un lot livre du code fonctionnel derrière les écrans, pas des écrans vides. |
| Pas de retard | Aucun jour calendaire n'est annoncé : la charge en points sert à comparer les lots et à arbitrer l'ordre interne. |

## 2. Vue d'ensemble des lots

| Lot | Contenu | Fonctions v1 livrées | Charge | Dépend de | État au 2026-10-26 |
|---|---|---|---|---|---|
| 0 | Monorepo, CI, design system, authentification | T1, T3 | 37 points | — | **Codé** — monorepo de 8 paquets, CI, design system de 48 widgets, session locale et Supabase |
| 1 | Structure narrative, éditeur par blocs, sauvegarde locale | O1 à O10, O12, E1 à E7, E10, E15, E16, P1 à P7 | 85 points | Lot 0 | **Codé** — éditeur de scène branché, base SQLite locale, plan et compteurs réels |
| 2 | CRDT, transport de synchronisation, multi-appareils | T4, T5, E11 | 62 points | Lot 1 | **Codé** — file d'attente durable, transport REST et WebSocket, fuzz de convergence |
| 3 | Révision, commentaires, présence, rôles | E17, C1 à C7 | 34 points | Lot 2 | **Partiel** — le panneau de relecture est livré : fils ancrés sur le texte, rôles de collaboration, résolution d'un fil ; la persistance des discussions est branchée ; la présence (C2) reste |
| 4 | IA : inline, plan, personnages, RAG, cohérence | A1 à A8, A13 | 56 points | Lots 2, 3 | **Partiel** — passerelle et action inline branchées, le plan et la cohérence restent |
| 5 | Exports EPUB, PDF, DOCX, couverture IA | E12, E13, E14, A11, B4 | 47 points | Lots 1, 4 | **Partiel** — les six formats sont générés, la couverture SVG est générée puis attachée aux exports ; le code-barres (B4) attend l'ISBN, le PDF n'embarque pas encore la couverture |
| 6 | Vitrine publique, Stripe, KDP | B1, B2, B3, B5, B6, B7, B8, B12 | 52 points | Lots 1, 5 | **Partiel** — le paiement est branché, la vitrine publique est servie (route publique sans jeton, page du livre, page de lecture et page de l'auteur) et l'auteur publie son livre depuis l'écran du projet (D-33) ; le dossier de dépôt KDP est préparé (EPUB, PDF d'impression, métadonnées validées, contrôle de soumission nominatif), le dépôt lui-même chez Amazon reste |
| 7 | Plans, quotas, administration, 2FA, RGPD | T2, T7, T8, T9, T10, T11 | 50 points | Lots 4, 6 | **Partiel** — l'export des données personnelles, la suppression du compte, la purge locale et le worker de purge serveur sont livrés ; les formules et les quotas (D-15), la double authentification TOTP, les rôles d'équipe et les sièges, le back-office, l'API publique et les webhooks sortants sont livrés et câblés ; la purge efface aussi le compte chez Supabase Auth et les artefacts du stockage |
| — | **Total v1** | **68 fonctions** | **423 points** | — | |

Note de comptage : FEATURE_MATRIX annonce 67 fonctions v1, mais le décompte
ligne à ligne de ses marques donne 68, dont T4 et T5 marquées ★ et non ●. Le
tableau suit le marquage ligne à ligne, plus précis que le résumé chiffré. La
fonction E14, marquée ◐, est livrée au lot 5 conformément à D-15, qui réserve
le PDF print-ready aux plans Pro et Studio.

## 3. Lot 0 — Socle

**Objectif.** Un dépôt qui s'analyse, se teste et s'exécute sur les six cibles, avec une authentification réelle et un design system réutilisable.

**Périmètre.** T1, T3. Socle technique de D-11 (design system en code), D-13 (polices embarquées), D-14 (4 thèmes), D-17 (i18n), D-21 (CI) et D-23 (monorepo).

**Dépendances.** Aucune : c'est le point de départ.

**Critères d'acceptation.**

- [ ] `flutter analyze` : 0 erreur, 0 avertissement sur `apps/` et `packages/` ; `dart format --set-exit-if-changed .` propre.
- [ ] La règle de dépendance de PROMPT §5 est vérifiée automatiquement par l'analyseur ; toute violation échoue la CI.
- [ ] 30 widgets du design system livrés, chacun couvert par au moins un test golden dans les 4 thèmes.
- [ ] Les 4 thèmes rendent les écrans de référence sans retouche.
- [ ] Inscription par lien magique, puis connexion OAuth Google et Apple, validées en environnement de test.
- [ ] JWT de 15 min, rotation du jeton de rafraîchissement, révocation serveur effective depuis la liste des appareils.
- [ ] `flutter test` vert et CI GitHub Actions exécutant analyse, tests et build web.
- [ ] Les 4 faces typographiques sont embarquées en assets ; aucune requête réseau de police au démarrage.

**Risques et parades.**

| Risque | Parade |
|---|---|
| Le fork de `flutter_quill` diverge de l'amont | L'API publique est isolée derrière des widgets Limpid (D-07) ; les correctifs sont reappliqués à chaque montée de version |
| La CI devient lente et discourage les contributions | Analyse et tests unitaires sur chaque PR ; goldens et build web sur les branches principales |
| Supabase Auth n'est pas disponible en local | Adaptateur d'authentification à double : un serveur de test local substitue GoTrue |

**Charge.** 37 points.

| Poste | Points | Poste | Points |
|---|---|---|---|
| Monorepo, règle de dépendance, analyseur | 5 | Authentification lien magique et OAuth | 5 |
| CI GitHub Actions, aperçus de PR | 3 | Sessions, appareils, révocation | 3 |
| Tokens et 4 thèmes | 5 | Squelette i18n `fr-FR` et `en-US` | 2 |
| 30 widgets du design system et goldens | 13 | Polices embarquées | 1 |

## 4. Lot 1 — Structure narrative et éditeur

**Objectif.** Écrire, réorganiser et suivre un manuscrit sans réseau, avec la hiérarchie à 5 niveaux et une persistance locale fiable.

**Périmètre.** O1, O2, O3, O4, O5, O6, O7, O8, O9, O10, O12, E1, E2, E3, E4, E5, E6, E7, E10, E15, E16, P1, P2, P3, P4, P5, P6, P7.

**Dépendances.** Lot 0.

**Critères d'acceptation.**

- [ ] Un projet contient une hiérarchie série → tome → chapitre → scène ; le chapitre est une vue ordonnée de scènes (D-02).
- [ ] Réordonner une scène ne déplace que l'index fractionnaire, jamais le texte.
- [ ] L'éditeur Delta gère gras, italique, titres, listes, citations, code et notes de bas de page ; les six formats sont couverts par des tests.
- [ ] Le menu slash ouvre la palette de commandes ; les modes focus, Zen et machine à écrire fonctionnent au clavier comme à la souris.
- [ ] Le glisser-déposer d'une scène conserve l'ordre après redémarrage.
- [ ] Le thème d'éditeur (police, taille, interligne, largeur de ligne) propose 6 préréglages et un réglage libre.
- [ ] La recherche plein texte renvoie un résultat correct sur 1 million de mots indexés en moins de 120 ms (budget ARCHITECTURE §9).
- [ ] Fermer l'application en cours d'écriture, puis la rouvrir : le texte est intégralement restauré, sans perte du dernier paragraphe.
- [ ] Objectif quotidien, objectif par livre et par scène, série de jours consécutifs, historique d'écriture, statistiques par scène et session d'écriture fonctionnent hors-ligne.

**Risques et parades.**

| Risque | Parade |
|---|---|
| Le lot est le plus lourd de la v1 | Découpage interne en deux tranches : structure et Story Bible d'abord, éditeur et progression ensuite ; le lot ne sort qu'entier |
| La dérive du fork éditeur bloque les fonctions d'édition | Le format de bloc CRDT est isolé dans `limpid_core` ; l'adaptateur Delta ↔ bloc est testable sans l'éditeur |
| La recherche locale devient lente sur un gros corpus | Index FTS5 externe recalculé par lot d'écritures, jamais à chaque frappe |

**Charge.** 85 points.

| Poste | Points | Poste | Points |
|---|---|---|---|
| Modèle local Drift, transactions | 5 | Thème d'éditeur (E5) | 3 |
| Hiérarchie à 5 niveaux (O1) | 5 | Bloc de scène et navigation clavier (E6) | 5 |
| Story Bible, fiches, chronologie, arcs, POV (O2 à O6) | 8 | Glisser-déposer des scènes (E7) | 5 |
| Étiquettes, collections, champs personnalisés (O7, O8) | 5 | Recherche et remplacement avec regex (E10) | 3 |
| Table des matières automatique (O10) | 3 | Autosave et reprise après crash (E15) | 5 |
| Recherche plein texte FTS5 (O9) | 5 | Raccourcis et palette de commandes (E16) | 3 |
| Pipeline brouillon → révision → publié (O12) | 2 | Objectifs, séries de jours, statistiques, sessions (P1 à P7) | 8 |
| Éditeur Delta et styles (E1) | 8 | Menu slash (E2) | 3 |
| Modes focus, Zen, machine à écrire (E3, E4) | 5 | — | — |

## 5. Lot 2 — Synchronisation

**Objectif.** Deux appareils hors-ligne modifient le même document et se réconcilient sans perte ni conflit arbitré par le dernier arrivé.

**Périmètre.** T4, T5, E11 (historique de versions et comparaison par bloc).

**Dépendances.** Lot 1.

**Critères d'acceptation.**

- [ ] Le fuzz multi-agents (2 rédacteurs, 1 relais, ordre de livraison aléatoire) prouve la convergence : tous les clients atteignent un état identique. Ce test est bloquant en CI.
- [ ] 1 000 opérations accumulées hors-ligne sont synchronisées en moins de 30 s une fois le réseau revenu.
- [ ] Une opération réémise après un délai de réponse perdu n'est appliquée qu'une fois (unicité de `(doc_id, lamport, author_id)`).
- [ ] Deux modifications concurrentes du même paragraphe sont fusionnées ligne par ligne, sans perte, sur les deux clients.
- [ ] Un déplacement concurrent et une modification de texte se réconcilient selon les règles de D-04, à l'identique sur tous les clients.
- [ ] La compaction produit un instantané au bout de 500 opérations et purge le journal sans perte de l'état.
- [ ] Un client dont la version de schéma est trop ancienne reçoit `409 schema_version_unsupported` puis se resynchronise depuis `GET /v1/projects/:id/tree` sans intervention de l'utilisateur.
- [ ] La propagation entre deux clients actifs reste sous 300 ms en p95.
- [ ] L'historique de versions compare deux révisions bloc par bloc.

**Risques et parades.**

| Risque | Parade |
|---|---|
| Une divergence de convergence n'est détectée qu'en production | Le fuzz est bloquant en CI et s'exécute à chaque changement de `limpid_core` (D-20) |
| La taille du journal `sync_ops` croît sans contrôle | Compaction automatique à 500 opérations, archive froide dans R2 |
| Le désordre de livraison casse la fusion 3-way | Ordre de Lamport local appliqué à la réception, aucune hypothèse sur l'ordre du réseau |

**Charge.** 62 points.

| Poste | Points | Poste | Points |
|---|---|---|---|
| Types de blocs, `OrderKey`, Lamport, opérations | 13 | `op_queue`, `outbox`, rejeu idempotent | 5 |
| Fusion 3-way du texte | 8 | Instantanés et compaction | 5 |
| Règles de conflits, tombstones, LWW | 5 | Migration de schéma et resynchronisation | 3 |
| Fuzz multi-agents | 8 | Intégration multi-appareils de bout en bout | 5 |
| Transport push et pull | 5 | Relais WebSocket et présence minimale | 5 |

## 6. Lot 3 — Révision et collaboration

**Objectif.** Relecture à plusieurs : commentaires ancrés au texte, présence visible, rôles maîtrisés.

**Périmètre.** E17, C1, C2, C3, C4, C5, C6, C7.

**Dépendances.** Lot 2.

**Critères d'acceptation.**

- [ ] Un commentaire s'ancre sur une plage de caractères et suit le texte quand le bloc est réécrit ; il est stocké comme surcharge du CRDT, donc jamais en conflit avec le texte.
- [ ] Un fil de discussion se répond, se résout et se rouvre.
- [ ] Deux personnes connectées voient la frappe de l'autre en moins de 300 ms.
- [ ] La présence affiche les curseurs distants et les avatars, et disparaît en moins de 30 s après déconnexion.
- [ ] Les rôles `propriétaire`, `co-auteur`, `bêta-lecteur` et `lecteur` sont appliqués côté serveur ; un bêta-lecteur ne peut pas modifier le texte.
- [ ] Un lien de partage en lecture ouvre le document sans compte et n'accorde l'écriture à personne ; il peut être révoqué.
- [ ] Un extrait publié devient visible sur la page publique du livre.
- [ ] Une invitation par courriel expire et ne peut pas être réactivée.

**Risques et parades.**

| Risque | Parade |
|---|---|
| La présence reste affichée après une coupure | Battement de vie de 25 s sur le WebSocket, purge automatique au-delà |
| Un lien partagé fuit vers un tiers | Jeton à usage unique, révocable, sans indexation ; pages partagées exclues du référencement |
| Les commentaires se perdent dans les fusions | Ce sont des marques additives dans le CRDT, jamais réécrits par une fusion de texte |

**Charge.** 34 points.

| Poste | Points | Poste | Points |
|---|---|---|---|
| Commentaires ancrés et fils de discussion (E17, C3) | 8 | Lien de partage en lecture (C5) | 3 |
| Édition temps réel (C1) | 5 | Publication d'extraits (C6) | 3 |
| Présence et curseurs distants (C2) | 5 | Invitations par courriel et expiration (C7) | 5 |
| Rôles et autorisations par ressource (C4) | 5 | — | — |

## 7. Lot 4 — IA

**Objectif.** L'IA porte sur le manuscrit entier, pas sur le paragraphe isolé, et reste sous contrôle de coût et de confidentialité.

**Périmètre.** A1, A2, A3, A4, A5, A6, A7, A8, A13.

**Dépendances.** Lots 2 et 3 : le texte et les commentaires sont déjà synchronisés, et le RAG s'appuie sur l'index des blocs.

**Critères d'acceptation.**

- [ ] Réécriture inline (étendre, raccourcir, simplifier, changer le ton) et continuation s'affichent en flux, sans blocage de l'éditeur ; le premier jeton arrive en moins de 2 s en p95.
- [ ] Génération d'un plan, de fiches personnages et d'un monde à partir d'un concept ; les résultats sont insérables en un clic.
- [ ] Le résumé de scène et de chapitre respecte le périmètre demandé.
- [ ] « Interroge ton livre » répond à partir du manuscrit seul et cite les scènes utilisées.
- [ ] Le contrôle de cohérence signale les divergences de noms, de chronologie et de contradictions, avec un lien vers la scène fautive.
- [ ] L'analyse de lisibilité renvoie un score Coleman-Liau et une indication de phrase longue.
- [ ] Chaque appel est compté, plafonné par le quota du plan et par une garde de jetons par requête et par jour.
- [ ] Aucun texte d'utilisateur n'atteint un fournisseur tiers sans consentement explicite enregistré dans les réglages.
- [ ] Le quota atteint renvoie `429 quota_exceeded` avec la date de réinitialisation, avant tout appel fournisseur.

**Risques et parades.**

| Risque | Parade |
|---|---|
| La facture IA dépasse la recette | Quotas par plan, budget guard par requête et par jour, alerte à 120 % du quota mensuel prévu |
| Le RAG cite des passages hors du manuscrit | Filtrage par `project_id` au niveau de la requête vectorielle, jamais par le texte du prompt |
| Le fournisseur d'IA est indisponible ou change d'API | Abstraction multi-fournisseurs et fournisseur de repli autorisé par le consentement |
| Des données supprimées restent indexées pour le RAG | Exclusion des index IA à la suppression de projet, purgée vérifiée par test |

**Charge.** 56 points.

| Poste | Points | Poste | Points |
|---|---|---|---|
| Passerelle multi-fournisseurs, budgets, quotas | 8 | RAG sur le manuscrit (A7) | 13 |
| Réécriture inline et continuation (A1, A2) | 8 | Contrôle de cohérence (A8) | 8 |
| Plan, personnages, monde (A3, A4, A5) | 8 | Analyse de lisibilité (A13) | 3 |
| Résumé de scène et de chapitre (A6) | 3 | Flux SSE, garde-fous, consentement | 5 |

## 8. Lot 5 — Exports et couverture

**Objectif.** Sortir du manuscrit des fichiers conformes aux plateformes de vente, et une couverture prête à publier.

**Périmètre.** E12, E13, E14, A11, B4.

**Dépendances.** Lots 1 (contenu) et 4 (couverture IA). L'export PDF print-ready est réservé aux plans Pro et Studio conformément à D-15, alors que FEATURE_MATRIX marque E14 en phase 2 : le générateur est livré, son activation est pilotée par le plan, ce qui lève la marque sans contredire D-15.

**Critères d'acceptation.**

- [ ] Import DOCX, Markdown, TXT, RTF, EPUB et ODT : le texte, les styles de titre et l'ordre des chapitres sont conservés.
- [ ] Export EPUB 3 valide : table des matières, métadonnées, navigation interne ; le fichier s'ouvre dans deux lecteurs de référence.
- [ ] Export PDF reflowable et PDF print-ready : marges, fond perdu, numérotation, polices embarquées, rendu identique hors-ligne.
- [ ] Export DOCX, HTML, Markdown et ODT : le document s'ouvre dans LibreOffice ou Word sans conversion manuelle.
- [ ] Export d'un projet de 80 000 mots : EPUB en moins de 8 s, PDF reflowable en moins de 20 s, PDF print-ready en moins de 45 s.
- [ ] Couverture IA : 5 images par mois sur le plan Écrivain, dimensions conformes aux prérequis des plateformes de vente.
- [ ] Maquette de couverture imprimable : dos, rectangle de tranche, code-barres EAN-13 valide.
- [ ] Un export raté n'est pas facturé et propose une relance ; l'artefact reste téléchargeable 15 minutes après notification.

**Risques et parades.**

| Risque | Parade |
|---|---|
| Le PDF print-ready varie selon la machine | Polices OFL embarquées et rendu déterministe ; test de rendu sur trois plates-formes |
| L'import dégrade la structure narrative | L'import construit des scènes, jamais un seul bloc ; la structure reste modifiable après import |
| Un export long bloque le worker | Job asynchrone avec file Redis, notification WebSocket, reprise après deux échecs |

**Charge.** 47 points.

| Poste | Points | Poste | Points |
|---|---|---|---|
| Import DOCX, Markdown, TXT, RTF, EPUB, ODT (E12) | 8 | Export DOCX, HTML, Markdown, ODT (E13) | 8 |
| Export EPUB 3 (E13) | 8 | Couverture générée (A11) | 5 |
| Export PDF reflowable et print-ready (E13, E14) | 8 | Maquette de couverture et code-barres (B4) | 5 |
| Job asynchrone, dépôt R2, notification | 5 | — | — |

## 9. Lot 6 — Vitrine, Stripe et KDP

**Objectif.** Publier, vendre et distribuer, de la page publique jusqu'à la précommande Amazon.

**Périmètre.** B1, B2, B3, B5, B6, B7, B8, B12.

**Dépendances.** Lots 1 et 5.

**Critères d'acceptation.**

- [ ] La page publique du livre affiche le titre, la couverture, le résumé, les chapitres publiés et les métadonnées commerciales.
- [ ] La page auteur liste ses livres, triés par date de publication.
- [ ] Les métadonnées ISBN, BISAC, contributeurs et droits sont saisies et validées au format avant publication.
- [ ] Un achat de bout en bout fonctionne en mode bac à sable Stripe : page de vente, paiement, réception du webhook, page de téléchargement.
- [ ] Le partage des revenus est par défaut à 90/10 et configurable.
- [ ] Un code promo, un livre gratuit et un bundle appliquent la remise correcte et la ventilation des droits.
- [ ] La soumission KDP met à jour une précommande existante sans dupliquer la fiche.
- [ ] La page de vente sert une URL de téléchargement stable, expirant après 24 heures ; les pages publiques sont indexables et les pages privées ne le sont pas.

**Risques et parades.**

| Risque | Parade |
|---|---|
| L'API KDP change sans préavis | Connecteur isolé, version d'API épinglée, adaptation par lot de livraison |
| Un webhook Stripe est joué deux fois | Traitement idempotent par identifiant d'événement, table des événements traités |
| La vitrine expose une œuvre non publiée | Contrôle de publication au niveau de l'API et de la requête, jamais du seul client |

**Charge.** 52 points.

| Poste | Points | Poste | Points |
|---|---|---|---|
| Vitrine du livre et catalogue de l'auteur (B1, B2) | 8 | Partage des revenus (B7) | 3 |
| Métadonnées ISBN, BISAC, contributeurs, droits (B3) | 5 | Page de vente et URL de téléchargement (B12) | 5 |
| Stripe Checkout et webhooks (B5) | 8 | Connecteur KDP et précommande (B8) | 13 |
| Codes promo, livre gratuit, bundle (B6) | 5 | Indexation et référencement de la vitrine | 5 |

## 10. Lot 7 — Plans, quotas, administration et RGPD

**Objectif.** Exploiter le service : plans payants, quotas appliqués, back-office et conformité.

**Périmètre.** T2, T7, T8, T9, T10, T11.

**Dépendances.** Lots 4 et 6 : la facturation s'appuie sur les quotas IA et sur les ventes.

**Critères d'acceptation.**

- [ ] Les quatre plans de D-15 sont purchasables, avec cycle mensuel et annuel et essai gratuit de 14 jours sur Écrivain.
- [ ] Chaque limite de plan est appliquée côté serveur et signalée avant qu'elle ne bloque : `402 plan_limit_reached` avec la fonctionnalité fautive nommée.
- [ ] La 2FA TOTP est obligatoire sur Pro et Studio, optionnelle ailleurs, et exigée à la connexion sur les plans concernés.
- [ ] Le back-office liste les utilisateurs, leur plan, leur usage, et permet d'activer ou de désactiver un indicateur de fonctionnalité.
- [ ] Les rôles d'équipe et les sièges sont gérés : 5 sièges sur Studio, refus d'une invitation au-delà.
- [ ] L'API publique et les webhooks sortants sont disponibles sur Studio, avec signature et secret rotatif.
- [ ] L'export RGPD produit un ZIP complet : manuscrits, assets, réglages, historique de compte.
- [ ] La suppression de compte passe en soft delete, purge définitivement au 30e jour et exclut les index IA.
- [ ] Les actions export, partage, suppression et changement de plan sont tracées dans `audit_log`.

**Risques et parades.**

| Risque | Parade |
|---|---|
| La facturation Stripe diverge du plan interne | Source de vérité unique : `subscriptions` et les webhooks reconstructent l'état, jamais le client |
| La 2FA bloque les utilisateurs légitimes | Codes de récupération à usage unique, procédure de réinitialisation vérifiée par un tiers |
| Un quota mal appliqué gêne un abonné | Compteurs lisibles par l'utilisateur, consommation affichée avant l'appel |

**Charge.** 50 points.

| Poste | Points | Poste | Points |
|---|---|---|---|
| Plans Stripe, cycle annuel, essai 14 jours | 8 | Rôles d'équipe et sièges (T11) | 5 |
| Compteurs de quota et budget guard | 5 | API publique et webhooks (T9) | 8 |
| 2FA TOTP obligatoire Pro et Studio (T2) | 3 | Export complet RGPD (T7) | 5 |
| Back-office utilisateurs et indicateurs (T10) | 8 | Suppression de compte et purge (T8) | 5 |
| Journal d'audit et registre RGPD | 3 | — | — |

## 11. Registre de risques

| Risque | Probabilité | Impact | Parade | Responsable |
|---|---|---|---|---|
| Divergence de convergence du CRDT en production | Moyenne | Critique | Fuzz multi-agents bloquant en CI, revue obligatoire de `limpid_core`, gel de version sur incident | Lead architecture |
| Dépassement du budget IA | Élevée | Élevé | Quotas par plan, budget guard par requête et par jour, alerte à 120 % du quota prévu | Lead API |
| Retard ou changement d'API KDP ou Stripe | Moyenne | Élevé | Connecteurs isolés et versionnés, environnement bac à sable, webhooks idempotents | Lead API |
| Dérive du fork `flutter_quill` | Élevée | Moyen | API publique isolée, correctifs reappliqués à chaque version, remplacement possible sans refonte | Lead client |
| Charge du lot 1 trop élevée pour un lot unique | Élevée | Moyen | Découpage interne en deux tranches, lot non mergé avant livraison complète | Lead produit |
| Fuite de données via la vitrine publique | Faible | Critique | Contrôle de publication côté API, indexation limitée aux pages publiées, audit des accès | Lead API |
| Base locale divergente du serveur | Moyenne | Moyen | Instantanés de compaction, resynchronisation complète, purge et reconstruction automatisées | Lead client |
| Perte de données lors d'une migration de schéma | Faible | Critique | Opérations en `pending_migration` jamais projetées ni supprimées, copie R2 avant migration | Lead architecture |
| Non-conformité RGPD constatée | Moyenne | Élevé | Export et suppression automatisés, registre des traitements, journal d'audit conservé un an | Responsable RGPD |
| Accessibilité non conforme sur un écran | Moyenne | Moyen | `Semantics` obligatoire, navigation clavier vérifiée à chaque lot, goldens sur les 4 thèmes | Lead client |
| Incohérence entre quotas annoncés et appliqués | Moyenne | Moyen | Compteurs serveur comme source unique, tests d'API sur chaque plan | Lead API |
| Coût de stockage supérieur aux prévisions | Faible | Moyen | Purge automatique du cache d'export à 500 Mo, plafond de stockage par plan | Lead API |
| Incident grave dans une chaîne d'approvisionnement | Faible | Critique | Verrouillage des versions, analyse de dépendances en CI, aucun secret en dépôt | Responsable sécurité |

## 12. Hors périmètre v1

### 12.1 Exclusions de D-24

| Exclusion | Rappel |
|---|---|
| Marketplace de templates payants | Pas de fragmentation du produit (FEATURE_MATRIX §5) |
| Publication livre par livre en batch | Publication unitaire uniquement |
| Intégration Notion bidirectionnelle | Aucun connecteur tiers de notes en v1 |
| Mode collaboratif à plus de 10 joueurs | Les rôles couvrent l'écriture à quelques (C4, T11) |
| Application iPad native | La cible iOS couvre le format ; pas d'application dédiée |
| Édition collaborative au caractère près | La collaboration v1 fonctionne au bloc, pas au caractère |

### 12.2 Fonctions reportées en phase 2

Marquées ◐ dans FEATURE_MATRIX, donc hors de la v1 :

| Identifiant | Fonction | Note |
|---|---|---|
| E8 | Lecture à voix haute locale | Non annoncée dans la v1 |
| E9 | Correcteur orthographique multilingue | Nécessite un dictionnaire embarqué, coût non justifié en v1 |
| A9 | Analyse de style et profil de voix | Partiellement couverte par A13 dans la v1 |
| A10 | Détection de clichés et mots répétés | Non couverte en v1 |
| A12 | Beat sheet trois actes ou Save the Cat | Non couvert en v1 |
| A14 | Traduction assistée du manuscrit | Non couverte en v1 |
| O11 | Relations entre scènes | Lien simple couvert par E11 en v1 |
| B9 | Connecteur Leanpub | Non couvert en v1, contrairement à B8 |
| B13 | Comptes rendus et avis | Non couverts en v1 |
| T6 | Mode local Ollama | Tension à trancher : D-08 et D-15 annoncent le mode local pour Studio, FEATURE_MATRIX le reporte. Le lot 4 livre l'architecture capable de router vers un modèle local ; l'activation par l'utilisateur reste hors v1 et devra être arbitrée par une nouvelle entrée de DECISIONS.md |
| T12 | Statistiques d'usage de l'auteur | Non couvertes en v1, contrairement aux compteurs d'exploitation du lot 7 |

## 13. Plan de test par lot

| Lot | Tests unitaires | Tests de widget | Golden | Convergence | E2E | Seuils |
|---|---|---|---|---|---|---|
| 0 | Analyse et format sur tout le dépôt | Navigation, formulaires d'authentification | 4 thèmes × 30 widgets | — | Inscription, connexion, 2FA | 0 erreur d'analyse, goldens stables |
| 1 | `limpid_core` ≥ 80 %, règles de progression, index fractionnaire | Éditeur, menus, glisser-déposer | Composants du design system | — | Création de projet, écriture hors-ligne, relecture | ≥ 70 % de couverture widget, frappe p95 < 16 ms |
| 2 | Opérations, Lamport, fusion 3-way, compaction | File d'attente, bandeau de synchronisation | — | Fuzz multi-agents, bloquant en CI | Écriture hors-ligne, retour réseau, convergence sur 3 clients | 100 % de convergence prouvée, propagation p95 < 300 ms |
| 3 | Ancrage des commentaires, rôles, jetons de partage | Filets de discussion, avatars | — | Fuzz conservé vert | Commentaire, présence, partage en lecture | Rôles vérifiés côté serveur, présence purgée en 30 s |
| 4 | Quotas, budget guard, RAG, lisibilité | Actions IA en ligne, états de flux | — | Fuzz conservé vert | Réécriture inline, interrogation du livre | Quota refusé avant appel fournisseur, premier jeton < 2 s |
| 5 | Générateurs EPUB, PDF, DOCX, HTML, Markdown, ODT | Aperçu d'export, galerie de couvertures | Rendu de couverture et de maquette | Fuzz conservé vert | Export, import, téléchargement signé | Fichiers conformes aux lecteurs de référence, exports dans les budgets |
| 6 | Partage des revenus, codes promo, webhooks | Page de vente, vitrine | — | Fuzz conservé vert | Achat en bac à sable, soumission KDP | Bilan exact, aucun double traitement de webhook |
| 7 | Quotas par plan, audit, purge RGPD | Écrans de compte et d'administration | — | Fuzz conservé vert | Changement de plan, export RGPD, suppression de compte | Quotas conformes à D-15, purge effective à 30 jours |

Règles transverses : `flutter analyze` et `dart format --set-exit-if-changed .`
doivent passer avant toute fusion ; le fuzz de convergence est exécuté sur
chaque PR qui touche `limpid_core` et bloque la fusion en cas d'échec (D-20) ;
les parcours hors-ligne sont rejoués sur les six cibles, car la synchronisation
n'est jamais un prérequis (PROMPT §2) ; chaque écran est vérifié dans les 4
thèmes et au clavier, avec un lecteur d'écran (D-18).

*Toute fonction ajoutée en cours de route doit être rattachée à un lot, ou
explicitement repoussée au §12 avec une décision datée dans `DECISIONS.md`.*
