# Limpid — Journal de décisions (ADR)

> Ce document verrouille les décisions prises en amont de toute implémentation.
> Chaque décision est **contraignante** : le code doit la respecter, une évolution
> passe par une nouvelle entrée datée.

**Projet** : Limpid — SaaS d'écriture et d'organisation de livres
**Stack imposée** : Flutter 3.44 / Dart 3.12
**Date de gel du socle** : 2026-10-25

---

## D-01 — Positionnement : B2C « studio d'écriture »

**Décision.** Limpid est un produit B2C pour auteurs indépendants. Un compte = un
auteur. Pas de multi-tenancy obligatoire, pas de SSO, pas de facture entreprise.

**Pourquoi.** Les plateformes de référence sont toutes B2C ou mono-écrivain
(Writebook, Inkwell, Papyrus Author, Anthra). Le multi-tenant B2B impose
isolation, RBAC, audit log et support — un coût opérationnel incompatible avec une
équipe de lancement.

**Conséquences.**
- Facturation Stripe en euros, au nom libre (l'utilisateur choisit son nom d'auteur).
- Les fonctionnalités d'équipe existent mais sont un *upgrade* (`Studio`), pas la base.
- Pas de concept d'« organisation » dans le modèle de données initial.

---

## D-02 — Modèle éditorial : hiérarchie à 5 niveaux, stockage en scènes

**Décision.**

```
Projet
└── Série            (optionnel, groupement d'ouvrages)
    └── Tome         (optionnel, subdivision d'une série)
        └── Chapitre (unité de publication)
            └── Scène (unité atomique de stockage et de synchronisation)
```

Une scène est l'unité **atomique** de stockage, de synchronisation et de version.
Le chapitre est une **vue** : un ensemble ordonné de scènes, éditable en
« flux continu » pour la relecture.

**Pourquoi.** Scrivener, Inkwell et Papyrus Author prouvent la valeur de la scène
(focus, réécriture, suivi de personnage). Bookish et Pressbooks prouvent qu'un
modèle à 2 niveaux est plus rapide à livrer mais perd la gestion narrative.
Le modèle hybride permet les deux lectures sans dupliquer les données.

**Conséquences.**
- Réordonnancement d'une scène = opération sur l'index fractionnaire, pas sur le texte.
- La « page » est un concept de lecture/estimation, pas une unité stockée.
- Les statistiques sont agrégées par scène → chapitre → tome → série.

---

## D-03 — Architecture : monorepo Dart, API Shelf sur Railway, Postgres managé

**Décision.**

| Couche | Choix |
|---|---|
| Client | Flutter (Web / iOS / Android / Windows / macOS / Linux) — un seul code |
| État | Riverpod 3 (code-gen) + `go_router` |
| API | Dart `shelf` + `shelf_router`, monolithe modulaire, déployé sur **Railway** |
| Base | **PostgreSQL** (Supabase managé ou Neon) — `postgres` + `drift` côté serveur |
| Auth | **Supabase Auth** (GoTrue) : magic link, OAuth Google/Apple, TOTP 2FA. JWT validés côté API via JWKS |
| Stockage fichiers | **Cloudflare R2** (S3 compatible) via `aws_s3` |
| Cache / files d'attente | **Redis** (Valkey) — file de jobs d'export et d'IA |
| Temps réel | WebSocket (WebSocketChannel) sur l'API — relais d'ops de sync |
| IA | Passerelle Dart multi-fournisseurs, Anthropic Claude par défaut |

**Pourquoi.** Un backend Dart garde la stack homogène (aucune linguagem de prod
secondaire), se déploie en un service Railway, et permet de partager le modèle
de domaine (`limpid_core`) entre client et serveur — donc entre le client et
l'API — sans duplication. Supabase Auth évite d'écrire de l'auth (XSS, session,
rotation de refresh token, 2FA) : c'est la surface la plus risquée du produit.

**Conséquences.**
- `packages/limpid_core` est pur Dart (zéro dépendance Flutter) : entités,
  opérations de sync, sérialisation, règles métier. Il est importé par le client
  ET par l'API. C'est le contrat de convergence.
- L'API est *stateless* ; l'état vit dans Postgres + Redis.
- Aucun accès direct du client à Postgres : tout passe par l'API (RLS possible
  en plus, pour les tables publiques de la vitrine).

---

## D-04 — Synchronisation : CRDT par bloc maison (« Limpid Sync »)

**Décision.** Implémentation Dart sur mesure d'un CRDT à granularité **bloc**,
inspirée de Yjs mais écrite en Dart pur (aucune dépendance Rust/WASM).

**Modèle.** Chaque document est un arbre de blocs. Chaque bloc possède :

```
Block {
  id       : ULID          // identifiant global, immuable
  doc      : DocumentId
  parent   : BlockId?      // hiérarchie (chapitre > scène > paragraphe)
  order    : OrderKey      // index fractionnaire lexicographique
  type     : BlockType     // paragraph, heading, list, quote, image, footnote…
  content  : BlockContent  // texte simple ou JSON riche (inline)
  marks    : Map<MarkId, Range>   // annotations IA, commentaires, notes
  lamport  : int           // compteur logique
  author   : AuthorId
  deleted  : bool          // tombstone
  version  : int
}
```

**Règles de résolution.**
1. **Structure** (déplacement, hiérarchie) : `order` est un index fractionnaire
   lexicographique ; deux insertions concurrentes entre les mêmes voisins
   convergent par comparaison lexicographique. Aucune perte, aucun conflit.
2. **Texte d'un bloc** : fusion 3-way par plus long préfixe/suffixe commun
   (diff-match-patch). Deux auteurs écrivant dans le même paragraphe fusionnent
   ligne par ligne, pas bloc par bloc.
3. **Tombstones** : suppression réversible, propagation par Lamport.
4. **Marquages** (commentaires, notes IA) : ensemble additif, union sans conflit.
5. **Métadonnées scalaires** (titre d'une scène) : LWW avec Lamport + tie-break
   par `authorId` — déterministe, identique sur tous les clients.

**Pourquoi pas Yjs/Automerge.** Les implémentations Dart sont peu matured ou
introduisent une dépendance Rust/WASM qui complique les builds mobiles et web.
Un CRDT par bloc écrit en Dart est testable, déterministe, sans dépendance
native, et **suffisant** : deux auteurs éditent rarement le même paragraphe
simultanément. Yjs reste une option de migration si la collaboration temps réel
à fort volume devient critique.

**Conséquences.**
- Le journal d'opérations est append-only en base : `sync_ops(doc_id, lamport, author_id, payload, created_at)`.
- Compaction : snapshot CRDT périodique (tous les N ops) + purge des ops antérieures.
- Hors-ligne : le client empile ses ops dans SQLite et les pousse au retour du réseau.
- Le désordre de livraison est géré : les ops sont idempotentes par `(doc_id, lamport, author_id)`.

---

## D-05 — Stockage local hors-ligne : Drift (SQLite) + FTS5

**Décision.** Base SQLite locale (Drift) en source de vérité pour l'affichage
hors-ligne, avec synchronisation opportuniste vers Postgres.

**Pourquoi.** SQLite + FTS5 donne la recherche plein texte locale (rapide, sans
serveur), le stockage de blobs (images, cache d'export) et l'atomicité via
transactions. Postgres reste la source de vérité multi-appareils.

**Conséquences.**
- Deux IVF : `documents` (CRDT compacts) et `documents_fts` (index FTS5 externe).
- Chiffrement au repos : SQLCipher en build desktop/mobile (option premium), volume
  chiffré sur le web via IndexedDB + WebCrypto.
- Purge : le cache local est reconstruit depuis le serveur au login si divergence de schéma.

---

## D-06 — État applicatif : Riverpod 3 (code-gen) + `go_router`

**Décision.** Riverpod avec `riverpod_generator` (annotations), providers scopés,
immutabilité stricte (cf. règles globales : jamais de mutation d'objets existants).

**Pourquoi.** Riverpod 3 offre `AsyncValue` (loading/error/data), invalidation
fine, dépendance explicite, testabilité sans boilerplate, et Riverpod 3 gère
mieux les scopes asynchrones (autoDispose) que Bloc.

**Conséquences.**
- Aucune gestion d'état mutable manuelle ; les états d'erreur sont des `AsyncError`
  typés avec message utilisateur.
- `go_router` pour le routing, avec redirections typées (auth guard, entitlement guard).

---

## D-07 — Éditeur : `flutter_quill` forké et étendu (« Limpid Quill »)

**Décision.** Base `flutter_quill` (Delta), forké en package interne
`packages/limpid_quill` avec les ajouts :

- Menu slash (`/`) avec blocs Étendu
- Poignées de glissement de blocs (drag & drop), avec position fractionnaire
- Actions IA en ligne (réécrire, étendre, raccourcir, changer le ton, traduire)
- Ancres de commentaires attachées aux plages de caractères
- Mode focus / machine à écrire / lecture seule
- Thème typographique éditable (police, taille, interligne, largeur de ligne)
- Sérialisation Delta ↔ format de bloc CRDT (adaptateur dans `limpid_core`)

**Pourquoi.** `flutter_quill` est le seul éditeur Flutter mature avec un modèle
Delta (JSON) qui supporte la collaboration (port Yjs existant, non utilisé ici) et
la sérialisation. Réécrire un éditeur rich text from scratch est hors budget.

**Contournement de la dette.** Le fork est maintenu **en amont** : les correctifs
sont ré-appliqués manuellement à chaque bump, et l'API publique est isolée derrière
des widgets Limpid pour permettre un remplacement ultérieur par un éditeur maison.

---

## D-08 — IA : passerelle Dart multi-fournisseurs

**Décision.** Service `limpid_ai` (dans l'API) qui abstracte Anthropic Claude,
OpenAI-compatible, et les modèles locaux (Ollama). Claude par défaut.

**Fonctions.** Génération de plan, personnages, monde ; réécriture inline ;
continuation ; résumé de chapitre ; contrôle de cohérence (personnages, chronologie,
hors-sujet) ; « interroge ton livre » (RAG sur le manuscrit via embeddings pgvector) ;
analyse de style (profil de voix) ; détection de clichés ; génération de couverture.

**Gouvernance des coûts.** Chaque appel est étiqueté (feature, utilisateur, plan),
compté dans un compteur, plafonné par le quota du plan. Un `budget guard` par
requête (tokens max) et par jour (tokens max) s'applique côté serveur.

**Confidentialité.** Par défaut, aucun texte d'utilisateur n'est envoyé à un
fournisseur tiers sans consentement explicite dans les réglages ; l'API propose
un mode « local only » (Ollama) pour les plans Studio.

---

## D-09 — Exports

**Décision.** Générateurs **natifs Dart** (pas de service externe par défaut) :

| Format | Bibliothèque | Usage |
|---|---|---|
| EPUB 3 | `epub` writer maison | Vente, KDP, Leanpub |
| PDF reflowable | `pdf` | Lecture, aperçu |
| PDF print-ready | `pdf` (polices OFL embarquées) | KDP, IngramSpark |
| DOCX | moteur maison (OOXML) | Manuscrits, soumissions |
| HTML | Dart | Vitrine publique, blog |
| Markdown | Dart | Interop, Writebook, git |
| ODT | `archive` + XML | LibreOffice |
| Kindle (KPF) | upload direct KDP | Amazon |

**Pourquoi.** Les exports natifs évitent les coûts et la latence d'un service
de conversion, et fonctionnent hors-ligne sur desktop. Les polices sont
embarquées (OFL) pour un rendu PDF déterministe et hors-ligne.

**Mise en œuvre réelle (vérifiée le 2026-10-25).**
- `printing` est un **plugin Flutter** : il ne peut pas être dépendance d'un
  package Dart pur. `Printing.sharePdf` et `PdfPreview` appartiennent à
  `apps/limpid_app`, pas au moteur d'export.
- Le paquet `docx` **n'existe plus sur pub.dev** (404, absent de l'API de
  recherche). Le DOCX est donc généré par le moteur lui-même : OOXML = ZIP + XML,
  comme l'EPUB et l'ODT. Dépendances finales du moteur : `archive`, `pdf`, `xml`.
- Tant que les quatre faces OFL ne sont pas dans `assets/fonts/`, le moteur PDF
  substitue des polices standard **et émet un avertissement** dans
  `ExportResult.warnings`. L'API d'enregistrement des polices est en place ; les
  fichiers de police sont à embarquer au lot 1.
- L'EPUB, l'ODT, le DOCX et le Markdown sont **reproductibles bit à bit** ; le PDF
  embarque la date de création système et ne l'est pas.

---

## D-10 — Distribution et vente

**Décision.** Suite de connecteurs serveur (OAuth + API) :
Amazon KDP (mise à jour d'une précommande = upload EPUB/PDF), Leanpub
(coupon, bundle, free book), Apple Books (via transcoder + API), Google Play
Books, Draft2Digital, Storyblocks. Paiement intégré : **Stripe Checkout**
(vente directe du livre + bagi-bagi 90/10 par défaut, configurable).

**Pourquoi.** C'est le créneau de Shaxpir / Leanpub que ni Bookish ni Inkwell
ne couvrent. Dans un modèle B2C, c'est un fort différenciateur — mais il vient
**après** l'éditeur dans l'ordre de livraison.

---

## D-11 — Design System : package Dart `limpid_design_system`

**Décision.** Le design system est du **code Dart**, pas un document :
`packages/limpid_design_system` expose `LimpidTheme` (light/sepia/dark/high-contrast),
les tokens (couleurs, typo, espacements, rayons, élévation, motion) et les
widgets de base. Les valeurs sont exportées en JSON (`tokens.json`) pour
alimenter Figma et les maquettes HTML.

**Pourquoi.** Un design system décrit dans un PDF finit toujours par dériver du
code. En Dart, la dérive est détectable par le compilateur et par les tests golden.

**Conséquences.**
- Tests golden sur les composants critiques (boutons, champs, cartes).
- L'UI web et mobile partagent le même code Flutter → cohérence garantie.
- Les maquettes HTML de `mockups/` sont générées à partir des mêmes valeurs de token.

---

## D-12 — Identité : « Limpid »

**Décision.** Nom **Limpid** (« limpide », « clair »). Signature : une page de
texte qui se clarifie. Marque sobre, éditoriale, chaleureuse — l'anti-« outil
d'IA violet ».

---

## D-13 — Langue et typographie

| Rôle | Face | Usage |
|---|---|---|
| Display / marque | **Fraunces** (variable, axes SOFT/WONK) | Titres d'écrans, nom de livre, chiffres clés |
| Interface | **Instrument Sans** | Navigation, boutons, formulaires, libellés |
| Manuscrit | **Literata** | Éditeur et lecteur de manuscrit |
| Données / technique | **IBM Plex Mono** | Métadonnées, compteurs, ISBN, logs |

**Pourquoi.** Fraunces est un serif variable à l personality editorial distincte
(absente des Inter/Space Grotesk par défaut). Literata est conçu pour la lecture
longue. Instrument Sans est un grotesque contemporain, non générique.

**Offline.** Les 4 faces sont **embarquées en assets** (OFL), jamais téléchargées
à l'exécution : `google_fonts` est interdit en production (il fetch au runtime et
casse le mode hors-ligne et le premier rendu).

---

## D-14 — Thèmes

| Thème | Usage | Fond |
|---|---|---|
| **Papier** (défaut) | Travail quotidien | `#FAF8F4` |
| **Sépia** | Lecture longue, mode "page" | `#F4EBD8` |
| **Nuit** | Écriture nocturne | `#14110E` |
| **Contraste élevé** | Accessibilité (WCAG AAA sur le texte) | noir/blanc |

Le thème est un choix utilisateur unique, global, synchronisé entre appareils.

---

## D-15 — Monétisation

| Plan | Prix | Inclus |
|---|---|---|
| **Gratuit** | 0 € | 1 projet, 10 000 mots, 50 exports/mois, IA limitée (2 réécritures/jour), stockage 100 Mo |
| **Écrivain** | 9,99 €/mois | 10 projets, 200 000 mots, IA standard, export illimité, synchro multi-appareils, couvertures IA (5/mois) |
| **Pro** | 24,99 €/mois | Projets illimités, IA premium, RAG sur le manuscrit, exports print-ready, KDP/Leanpub, 1 Go stockage |
| **Studio** | 49,99 €/mois (ou 499 €/an) | 5 sièges, rôles, mode local (Ollama), API & webhooks, SSO light, support prioritaire |

Facturation Stripe, cycle mensuel/annuel, essai gratuit 14 jours sur Écrivain.

---

## D-16 — Collaboration et rôles

**Décision.** Collaboration temps réel (opérations CRDT propagées en < 300 ms
sur le même document) avec **présence** ( curseurs distants et avatars).

Rôles : `propriétaire`, `co-auteur` (édition), `beta-lecteur` (commentaires
uniquement), `lecteur` (lecture seule), `invité externe` (lien public limité).

**Décision de sécurité.** Les commentaires sont des surcharges (marks) dans le
CRDT → jamais de conflit avec le texte, et mergeables hors-ligne.

---

## D-17 — Internationalisation

**Décision.** `fr-FR` par défaut, `en-US` complet, `es-ES`, `de-DE`, `pt-BR`
préparés (fichiers de traduction + RTL ready via `intl`). L'{'{'}arabe{'}
n'est pas supporté en v1 mais le code le foresee (pas de concatenation manuelle,
`flutter_localizations` + `Directionality`).

**Pourquoi.** L'écosystème cible (Écrivains francophones) → français d'abord,
anglais pour l'international. Les chaînes ne sont jamais codées en dur dans les widgets.

---

## D-18 — Accessibilité : WCAG 2.2 AA minimum

**Décision.** Cible **WCAG 2.2 niveau AA**, AAA sur le texte du lecteur.
Exigences non négociables :

- Cible tactile ≥ 44 × 44 px ; focus visible (2 px + décalage) sur tous les contrôles
- Navigation clavier complète ; raccourcis documentés dans l'éditeur
- `Semantics` Flutter sur chaque widget interactif ; lecteurs d'écran testés (NVDA, VoiceOver)
- Animation désactivée si `MediaQuery.disableAnimations`
- Contraste : 4,5:1 (texte courant), 3:1 (grand texte, icônes, focus)
- Le mode « Contraste élevé » est une exigence, pas une option premium
- Aucun sens porté uniquement par la couleur (statuts = couleur + icône + texte)

---

## D-19 — Sécurité

| Contrôle | Décision |
|---|---|
| Mots de passe | Argon2id (Supabase Auth), jamais de hash custom |
| Sessions | JWT court (15 min) + refresh rotatif, révocation serveur |
| 2FA | TOTP obligatoire pour les plans Pro/Studio, optionnelle ailleurs |
| Données au repos | TLS 1.3 en transit ; SQLCipher local ; R2 chiffré (SSE) |
| E2EE | Option premium : chiffrement client du contenu des ouvrages (chiffrement envelope par clé de document) — lisibilité seule, IA et export désactivés |
| Secrets | Variables d'environnement / gestionnaire, jamais en dépôt |
| Isolation | Row-Level Security sur toutes les tables multi-utilisateur (livres publics en lecture seule) |
| Audit | `audit_log` sur actions sensibles (export, partage, suppression, changement de plan) |
| Export utilisateur | ZIP complet (manuscrits + assets + settings) — obligation RGPD |
| Suppression | Soft delete 30 jours + purge définitive de toutes les tables personnelles + exclusion des index IA |
| Purge (portée et exceptions) | La purge efface les tables déclarées comme personnelles dans `apps/limpid_api/lib/src/db/personal_data_tables.dart` ; un test échoue si une table du schéma n'est pas déclarée. Sont conservés, avec la raison écrite dans la déclaration : le journal d'audit (un an, D-19), le registre des purges, la trace des suppressions des tiers et les événements Stripe (aucune donnée personnelle). L'indicateur de fonctionnalité reste — c'est la configuration du service — mais l'identifiant de l'administrateur qui l'a changé est vidé |
| Analyse continue | Audit OSV des dépendances Dart + CodeQL sur l'outillage JavaScript — voir D-35 |

---

## D-20 — Tests et qualité

| Niveau | Cible | Outils |
|---|---|---|
| Unitaires | ≥ 80 % sur `limpid_core` | `test` |
| Convergence sync | 100 % — fuzz multi-agents (2 Writers + Relais) | `test` + `fastcheck` |
| Widget | ≥ 70 % | `flutter_test` |
| Golden | Composants DS | `golden_toolkit` |
| E2E | Parcours critiques (signup, écriture hors-ligne, sync, export, achat) | `integration_test` |
| Qualité | `flutter analyze` strict, `dart format`, `very_good analysis` | CI |

**Règle critique.** La convergence du CRDT est la propriété la plus importante
du produit : tout changement dans `limpid_core` doit faire passer le fuzz test.

---

## D-21 — CI/CD et déploiement

- **GitHub Actions** : `analyze` → `test` (unit + golden) → `build web` → `build desktop` → `build android/ios` (sur tag) → déploiement Railway sur `main`.
- **Preview** : chaque PR ouvre un preview web (build web statique) avec un canal de test de sync.
- **Migrations** : SQL versionnés dans `supabase/migrations`, appliqués par la CI avant déploiement.

---

## D-22 — Web = PWA

**Décision.** La cible web est une **PWA installable** (manifest, service worker
pour le shell applicatif, cache des polices embarquées). Le service worker ne cache
**jamais** les réponses API containing des données private.

---

## D-23 — Structure du monorepo

```
Limpid/
├─ apps/
│  ├─ limpid_app/          # Flutter : web + mobile + desktop
│  └─ limpid_api/          # Dart Shelf sur Railway
├─ packages/
│  ├─ limpid_core/         # Dart pur : entités, CRDT, règles métier
│  ├─ limpid_design_system/# Dart : tokens + widgets
│  ├─ limpid_quill/        # Fork éditeur
│  ├─ limpid_ai/           # Passerelle IA (client partagé)
│  ├─ limpid_export/       # Générateurs EPUB/PDF/DOCX
│  └─ limpid_sync/         # Client de synchronisation + transport
├─ docs/
├─ mockups/
```

---

## D-24 — Limites explicites de la v1

Pour éviter l'étalement : **hors v1** = marketplace de templates payants,
publication livre par livre en batch, intégration Notion bidirectionnelle, mode collaboratif
à plus de 10 joueurs, application iPad native, édition collaborative en direct
sur texte au caractère près (hors blocs).

---

## D-25 — Ce qui n'est PAS décidé ici (à trancher plus tard)

- Format de sérialisation finale du CRDT sur disque (binaire `Uint8List` vs JSON)
- Choix du fournisseur d'embeddings (pgvector + quel modèle)
- Stratégie de facturation à l'usage de l'IA (tokens vs crédits)
- Modèle d'arrondi monétaire (Stripe rounding vs Decimal maison)

---

## D-26 — Granularité de fusion du contenu riche

**Décision.** La fusion 3-way opère sur la **projection texte** d'un bloc. En
l'absence de conflit, le delta riche (`InlineContent`) est conservé intact. Quand
un conflit force une fusion, le bloc retombe en texte simple : les marques
inline concurrentes sur ce bloc sont perdues.

**Pourquoi.** Fusionner deux deltas riches (deux jeux de marques qui se
chevauchent) n'a pas de solution triviale et sans perte. La projection texte
garantit la propriété qui compte — *aucun caractère n'est perdu* — et laisse la
reconstruction du delta à l'étage supérieur.

**Conséquences.**
- L'adaptateur `limpid_quill` (lot 1) doit réappliquer les marques inline après
  une fusion, à partir des `marks` (commentaires, notes IA) stockés séparément
  dans le CRDT — ils ne sont pas perdus, eux.
- Un bloc fusionné est marqué `richContentLost` dans l'état effectif pour que
  l'interface puisse proposer « Restaurer la mise en forme » à l'utilisateur.
- Le test de fuzz de convergence compare la **projection texte** ; une seconde
  assertion compare les marques, qui doivent converger par union additive.

---

## D-27 — Versionnement de Riverpod et de la génération de code

**Décision.** Le trio `riverpod 3.0.3` · `riverpod_annotation 3.0.3` ·
`riverpod_generator 3.0.3`, avec `build_runner` dans la série 2.4–2.6.

**Pourquoi.** L'écosystème pub impose un verrou de versions que le PROMPT ne
pouvait pas anticiper :

| riverpod_generator | exige `build` | exige `analyzer` | build_runner compatible |
|---|---|---|---|
| 4.0.9 | `>=3.0.0 <5.0.0` | `>=13.0.0 <15.0.0` | aucun (les build_runner 2.7+ exigent `build >= 5.0.0`) |
| 3.0.3 | `>=3.0.0 <5.0.0` | `>=7.0.0 <9.0.0` | 2.4 – 2.6 (`analyzer < 9.0.0`) |

La série 4 du générateur ne peut donc pas coexister avec une version de
`build_runner` published à ce jour. La série 3 le peut, mais elle **épingle
`riverpod` à 3.0.3 exactement** — d'où la borne `flutter_riverpod
>=3.0.3 <3.1.0` dans `apps/limpid_app/pubspec.yaml`.

**Conséquences.**
- La génération de code Riverpod est conservée (PROMPT §4) : les providers sont
  annotés `@Riverpod` et le code est produit par `build_runner`.
- `riverpod_generator` 3.x suffixe le nom du provider généré par `Provider`
  quand la fonction porte déjà ce suffixe : `dailyGoal` produit
  `dailyGoalProvider`, `dailyGoalProvider` produirait
  `dailyGoalProviderProvider`. **Les fonctions de provider ne doivent donc pas
  se terminer par `Provider`.**
- Une montée vers `riverpod_generator` 4.x se fera quand l'écosystème pub
  publiera un `build_runner` compatible avec `build < 5.0.0`, ou par abandon du
  codegen au profit des providers manuels de Riverpod 3.4.

---

## D-28 — Casse des libellés de bouton

**Décision.** Les libellés de bouton restent en **casse de phrase**. La mise en
capitales du token `label` est réservée aux libellés de formulaire et aux
titres de section.

**Pourquoi.** DESIGN_SYSTEM.md §3.3 interdit les capitales au-delà de trois
mots. Or les actions de Limpid sont précisément des phrases : « Recevoir mon
lien d'accès », « Ajouter à la chronologie », « Exporter les métadonnées ». Les
mettre en capitales produirait six blocs de capitales illisibles dans une
interface française.

**Conséquences.**
- `LimpidButton` n'applique plus `LimpidTextTransform.label`. Le helper reste
  disponible pour les libellés courts.
- Les tests du design system qui attendaient des capitales ont été mis à jour.

---

## D-29 — PostgreSQL en production, SQLite en développement

**Décision.** La base serveur reste **PostgreSQL** en production (Supabase
managé). En développement, l'API démarre par défaut sur **SQLite**, un fichier
local, sans service à installer. Le choix se fait par la variable
d'environnement `LIMPID_DB_DRIVER` (`sqlite` par défaut, `postgres` sur
demande) ; `LIMPID_DB_PATH` fixe le chemin du fichier SQLite.

**Pourquoi.**

| Contrainte | Effet sur le poste de développement |
|---|---|
| 7,3 Go de RAM, Docker Desktop lancé en permanence | PostgreSQL + Docker consomment la mémoire disponible et tuaient les builds Flutter |
| Le client (application) stocke déjà en SQLite via Drift | Le serveur en SQLite **parle le même langage de données** que le client : mêmes types, mêmes transactions |
| L'API passe déjà par des ports (`ProjectStore`, `SyncStore`, `AuditLog`) | Le moteur est un détail d'infrastructure : le substituer ne touche pas le domaine |

Un poste neuf doit pouvoir lancer `dart run bin/server.dart` **sans installer
Postgres**. C'est la condition pour que le dépôt soit exploitable en deux
minutes.

**Conséquences.**
- Les requêtes restent **paramétrées** et le dialecte est confiné aux
  adaptateurs : `SqliteProjectStore`, `SqliteSyncStore`, `SqliteAuditLog`
  vivent à côté de leurs homologues Postgres et implémentent les mêmes
  interfaces.
- Les migrations sont **dupliquées par dialecte** : `db/migrations/*.sql`
  (Postgres) et `db/migrations/sqlite/*.sql` (SQLite). Les deux jeux doivent
  rester équivalents : mêmes tables, mêmes colonnes, mêmes index, mêmes
  unicités.
- `DATABASE_URL` n'est obligatoire **que** lorsque `LIMPID_DB_DRIVER=postgres`.
  La validation de la configuration est donc conditionnelle, jamais implicite.
- L'API distingue deux **profils** de configuration. En profil `dev`, les
  services distants (Supabase, R2, Anthropic, Stripe) sont facultatifs et
  reçoivent des valeurs de substitution explicites : le serveur démarre sur
  une machine neuve, `/health` répond, et les requêtes qui exigent le vrai
  service sont rejetées proprement. Redis est optionnel : le cache se désactive
  et la file d'attente refuse les jobs avec une erreur explicite, jamais un
  plantage au démarrage. En profil `prod`, **toute** variable manquante
  empêche le démarrage : la production ne tourne jamais avec des valeurs de
  substitution.
- **Les deux moteurs sont prouvés équivalents par les mêmes tests** : les
  scénarios de dépôt sont exécutés contre les deux implémentations. Un test
  qui ne passe que sur l'un des deux est un bug, pas une différence de
  dialecte.
- La CI valide les **deux** dialectes : le job `db-migrations` applique les
  migrations PostgreSQL à un service `postgres:16-alpine`, applique les
  migrations SQLite à un fichier local, puis compare les deux schémas table
  par table et colonne par colonne. Un dialecte qui dérive de l'autre casse
  la CI, pas l'application.
- SQLite est **interdit en production** : le mode mono-écrivain ne supporte ni
  la convergence multi-appareils ni les écritures concurrentes du relai de
  synchronisation.
- Différences de dialecte assumées : `TIMESTAMPTZ` → `INTEGER` (microsecondes
  depuis l'époque Unix, UTC), `UUID` → `TEXT`, `JSONB` → `TEXT`, `BOOLEAN` →
  `INTEGER` (0/1), `SERIAL` → `INTEGER PRIMARY KEY AUTOINCREMENT`, `ILIKE` →
  `LIKE` (SQLite est insensible à la casse pour l'ASCII), `USING GIN`/
  `text_pattern_ops` supprimés.
  L'horodatage en microsecondes est préféré au format ISO 8601 textuel : un
  entier trie exactement comme un `TIMESTAMPTZ` et conserve la résolution à la
  microseconde de `DateTime`, qu'une colonne textuelle perdrait. La conversion
  est écrite **en un seul endroit**, `SqliteValues`, jamais dispersée dans les
  adaptateurs.
- SQLite n'a pas de fonction `now()` : **le code fournit toujours
  l'horodatage**. Les colonnes `created_at` n'ont donc pas de valeur par
  défaut dans le dialecte SQLite, là où PostgreSQL en a une. C'est la seule
  divergence de schéma tolérée, et elle est vérifiée : les deux jeux de
  migrations sont comparés table par table et colonne par colonne par la CI.

---

## D-30 — Version de `sqlite3` et épinglage `meta` du SDK Flutter

**Décision.** `sqlite3` est borné à `>=3.5.2 <3.8.0` dans l'application
Flutter et dans les dépendances de développement des paquets Dart purs.
`packages/limpid_sync` ne déclare **plus** `sqlite3` en dépendance de
production : Drift laisse l'ouverture de la base à l'application appelante,
et le package n'importe jamais `package:sqlite3`.

**Pourquoi.** Le SDK Flutter 3.44 épingle `meta` à `1.18.0` exactement. Or
la chaîne de dépendances est la suivante :

| Paquet | Contrainte | Effet |
|---|---|---|
| `sqlite3 3.8.0` | `hooks: ^2.2.0` | tire `hooks 2.2.0` |
| `hooks 2.2.0` | `record_use: ^1.0.0` | tire `record_use 1.x` |
| `record_use 1.x` | `meta: ^1.19.0` | **incompatible** avec `meta 1.18.0` |

La résolution échoue donc dès qu'une application Flutter dépend d'un paquet
qui impose `sqlite3 3.8.0` — c'est exactement ce que faisait
`packages/limpid_sync`, sans jamais l'utiliser. `sqlite3 3.5.2` accepte
`hooks 2.0.2`, qui tire `record_use 0.6.0` et `meta ^1.17.0` : la chaîne
reste compatible.

**Conséquences.**
- `packages/limpid_sync` ne peut plus garantir par lui-même la présence de
  `sqlite3` : l'application qui l'embarque doit le déclarer. C'est la
  pratique attendue de Drift, qui laisse le `QueryExecutor` à l'appelant.
- `apps/limpid_api` reste sur `sqlite3: ^3.8.0` : c'est un paquet Dart pur,
  sans épinglage Flutter, et la version la plus récente y est préférable.
  Les deux versions sont testées par le même contrat de dépôt.
- Toute montée de `sqlite3` au-delà de `3.7.x` doit être vérifiée **dans
  l'application Flutter** avant d'être acceptée, pas seulement dans le
  paquet Dart pur : c'est là que l'épinglage `meta` se manifeste.
- Le dépôt mentionne cette contrainte à chaque endroit où `sqlite3` est
  déclaré, pour qu'un `pub upgrade` ne casse pas la résolution sans
  explication.

---

## D-31 — Couches de l'application : contrat, implémentation, écrans

**Décision.** L'application `apps/limpid_app` suit trois couches, séparées
par le dossier qui les contient :

| Couche | Dossier | Rôle |
|---|---|---|
| Contrat | `lib/src/domain/` | Les interfaces `ManuscriptRepository`, `SyncRepository`, `ExportRepository`, `AiRepository`, l'enum `SyncStatus` et les types de valeur |
| Implémentation | `lib/src/data/` | La base SQLite (Drift), le client HTTP, la synchronisation |
| Écrans | `lib/src/features/` | L'interface, un dossier par fonctionnalité |

Le point de composition est **unique** : `lib/src/app/dependencies.dart`.

**Pourquoi.** La règle de dépendance de PROMPT §5 s'applique autant à
l'intérieur de l'application qu'entre les paquets. Un écran qui dépend
d'une base SQLite ou d'une URL d'API ne peut plus être testé sans réseau ni
sans fichier ; il ne peut plus décider si la donnée vient du serveur ou du
téléphone. En passant par un contrat, l'écran ne sait **que** ce qu'il
demande, et la décision « local d'abord » reste au point de composition.

C'est aussi ce qui rend le mode hors ligne possible sans état particulier :
le contrat répond toujours depuis la base locale, la synchronisation est une
autre implémentation qui travaille en arrière-plan.

**Conséquences.**
- Un écran se teste avec un **dépôt factice** écrit à la main : pas de
  mock généré, pas de base de données dans un test de widget.
- Une capacité optionnelle se déclare par une interface qui **étend** le
  contrat (`PendingChangesSyncRepository`), jamais par une méthode ajoutée au
  contrat : ajouter une méthode casse toutes les implémentations.
- Les providers Riverpod du contrat sont écrits **à la main** dans le point
  de composition, jamais par génération : la génération de code dans un
  paquet partagé par plusieurs agents est une source de conflits, et le
  contrat n'a besoin d'aucune annotation.
- L'API n'est jamais appelée directement depuis un écran : le client HTTP
  appartient à la couche d'implémentation.
- Les ports sont **uniques** : `lib/src/domain/providers.dart` déclare les
  ports de l'application — le manuscrit, la synchronisation, les préférences,
  les exports, l'assistant, les données personnelles et l'auteur — et rien
  d'autre ne déclare un provider portant le même nom. Un contrat propre à une
  fonctionnalité (les discussions de la relecture, la page publique d'un
  livre) reste **dans** sa fonctionnalité, mais son implémentation durable
  vit dans `lib/src/data/` et le point de composition la branche. Un port dont
  l'implémentation n'est pas encore branchée lève une exception — sauf ceux
  dont l'absence est sans conséquence, qui rendent une doublure en mémoire
  ou une doublure qui refuse l'appel avec une raison explicite.
- Les **exceptions** appartiennent au domaine : `lib/src/domain/errors.dart`
  déclare le vocabulaire des erreurs, et `lib/src/data/` les lève. Un écran
  doit pouvoir nommer l'erreur qu'il affiche sans importer la couche
  d'implémentation.
- La base locale qui ne s'ouvre pas ne fait pas tomber l'application : le
  point de composition bascule sur les doublures en mémoire, et l'interface
  dit que les manuscrits ne sont pas persistés. C'est le cas du **web**,
  où Drift a besoin du module WebAssembly de SQLite pour s'ouvrir.

---

## D-32 — Base locale sur le web : les deux fichiers de Drift sont versionnés

**Décision.** `apps/limpid_app/web/sqlite3.wasm` et
`apps/limpid_app/web/drift_worker.js` sont **versionnés**. Ils sont
copiés du paquet `drift` du cache pub par
`apps/limpid_app/tool/setup_web_assets.py`.

**Pourquoi.** Drift n'ouvre une base SQLite dans un navigateur qu'avec deux
fichiers servis à côté de `index.html` : le moteur compilé en WebAssembly, et
le worker qui le fait tourner hors du fil principal. Sans eux, la
construction web produit une application qui démarre et qui **n'ouvre pas sa
base** : l'auteur ne peut pas écrire.

Les versionner est un choix, pas une facilité : un binaire de 758 Ko dans le
dépôt. Les alternatives sont pires — les compiler à la construction exige une
chaîne d'outils native dans la CI, et les télécharger à l'exécution rend le
démarrage dépendant du réseau, ce qui contredit la promesse hors ligne. Le
fichier est **vérifiable** : c'est la copie exacte du paquet `drift` que le
projet utilise, et le script qui la produit est versionné avec lui.

**Conséquences.**
- Toute montée de version de `drift` impose de relancer
  `python apps/limpid_app/tool/setup_web_assets.py` : les deux fichiers doivent
  correspondre à la version du paquet.
- Le **web** reste le seul poste où la base locale peut manquer. Le point de
  composition bascule alors sur les doublures en mémoire (D-31) : l.author
  continue d'écrire, l'interface dit que le manuscrit n'est pas persisté.
- Les deux fichiers sont servis par la construction Flutter : ils sont
  copiés dans `build/web/` avec le reste de `web/`, sans configuration
  supplémentaire.

---

## D-33 — Publier un livre : deux états, pas un

**Décision.** La publication d'un livre tient dans **deux colonnes**, pas une :

- `ManuscriptStatus.published` — l'état de travail du manuscrit, dans le
  domaine (`packages/limpid_core`), dans la base locale de l'appareil et dans
  le CRDT. Il dit où en est l'écriture.
- `is_public` — la visibilité, sur le serveur (`apps/limpid_api`). Il dit si
  le livre est en vitrine.

Un livre n'apparaît dans la vitrine que si le serveur le sait **publié**
(`status = 'published'`) **et** **public** (`is_public = TRUE`). L'action de
publication de l'application écrit les deux.

**Pourquoi.** « Publié » et « en vitrine » ne sont pas la même question. Un
auteur termine son manuscrit et veut le relire avant de le vendre ; il lui
faut un livre **publié** qui n'est **pas** encore public. Réduire les deux à
un seul état prendrait cette possibilité, ou — à l'inverse — exposerait le
livre dès la fin de la rédaction.

Le choix a un coût : les deux colonnes doivent voyager. La table `projects`
de la base **locale** de l'appareil porte donc `is_public` comme la table
`projects` du serveur. Sans cela, le synchroniseur ne peut pas transmettre
l'intention de publier, et le livre resterait `published` sur l'appareil et
invisible sur le serveur.

**Conséquences.**
- `packages/limpid_core` porte `Project.isPublic` ; la base locale porte la
  colonne `is_public` ; le synchroniseur l'envoie au serveur avec l'état du
  manuscrit.
- La route publique `GET /v1/public/books/<id>` répond **404** pour un
  livre qui n'est pas publié **et** public. Elle ne distingue jamais
  l'absence du projet de son caractère non publié : la réponse ne doit rien
  laisser deviner de l'existence d'un manuscrit privé.
- La page publique ne porte que l'extrait d'une scène, jamais son texte
  entier.
- La route publique est `GET /v1/public/books/:projectId` : le livre est
  identifié par son projet, et non par un slug. Le slug vient avec la
  distribution (KDP) ; il n'a pas à être inventé avant.
- La route est **publique** : elle répond sans jeton, elle est limited en
  débit, et elle ne lit le journal du manuscrit qu'après avoir prouvé que le
  livre est publié et public — un livre privé ne doit pas se distinguer, ne
  serait-ce que par son temps de réponse, d'un livre qui n'existe pas.


---

## D-34 — L'identifiant d'un livre : le serveur le fabrique, l'appareil l'adopte

**Décision.** Quand l'application inscrit un livre auprès du serveur, le
serveur **fabrique** l'identifiant (`POST /v1/projects` ne lit pas
l'identifiant du corps) et l'appareil **adopte** celui qu'il reçoit : quand
la réponse porte un autre identifiant que celui du projet local, une seule
transaction renomme le projet et tout ce qui y renvoie — les chapitres,
l'index des documents, les collaborations — et l'ancien identifiant devient
un **alias** du nouveau.

**Pourquoi.** L'API est figée : le port `ProjectStore.create` n'a pas de
paramètre `id`, et les trois implémentations (SQLite, PostgreSQL, mémoire)
appelent toutes `UlidGenerator().generate()`. On ne peut donc pas faire
adopter au serveur l'identifiant du client.

Ce n'est pas un détail : la vitrine est adressée par l'identifiant **local**
(`/vitrine/<project.id>` → `GET /v1/public/books/<id>`). Les deux
identifiants doivent donc converger, sinon la vitrine pointe sur un livre
qui n'existe pas. Adopter l'identifiant du serveur est la seule règle qui
reste correcte avec une API figée.

**L'ordre des règles.** L'appareil n'a jamais besoin du réseau pour créer un
livre : il garde son identifiant jusqu'à la première inscription réussie. Le
livre existe donc hors ligne, et le synchroniseur le déclare au serveur dès
qu'il peut.

**Conséquences.**
- `ProjectIdentityStore` écrit l'alias dans les préférences : une écriture
  qui porte encore l'ancien identifiant atterrit sur le projet lui-même,
  jamais sur une seconde ligne.
- L'appareil envoie déjà son `id` dans le corps de la création : le jour où
  le serveur l'accepte, l'adoption n'a plus lieu. C'est la voie
  suivie pour la suite, et elle supprime la cascade de renommage.
- Un livre **sans scène** n'a aucune opération à pousser : il ne serait
  jamais déclaré au serveur, et la vitrine ne le montrerait pas. La
  synchronisation déclare donc, à chaque tour, les livres de l'auteur qui
  n'ont pas encore de scène.
- Les deux états de la publication (D-33) voyagent par `PATCH` : le
  serveur crée toujours un livre `is_public = false`, et le titre n'est pas
  dans le CRDT — le renvoyer permettrait au dernier appareil synchronisé
  d'écraser silencieusement les autres.

---

## D-35 — Chaîne de sécurité continue : audit OSV des dépendances Dart

**Date** : 2026-10-26

**Décision.** La chaîne de sécurité continue du monorepo repose sur deux
contrôles :

- **Audit des dépendances Dart** — `tools/osv_audit.dart` lit les fichiers
  `pubspec.lock` résolus et interroge le registre OSV des vulnérabilités
  connues (https://osv.dev). Le job `dependency-audit` de
  `.github/workflows/security.yml` échoue dès qu'une dépendance est connue
  pour une vulnérabilité.
- **Analyse CodeQL** — limitée au JavaScript de l'outillage des maquettes
  (`mockups/tools/`), le seul langage du dépôt que GitHub sait encore
  analyser.

**Pourquoi.** GitHub a retiré Dart des langages pris en charge par CodeQL :
l'action d'initialisation échoue sur une langue inconnue (« Did not recognize
the following languages: dart ») et le check de l'analyse reste rouge sur
chaque commit. Garder ce job en l'état revient à afficher un échec permanent
sur le dépôt ; le supprimer sans rien mettre à la place laisse les
dépendances Dart sans surveillance.

L'audit OSV comble ce manque : le registre des vulnérabilités est
indépendant du langage, il se consulte par paquet et par version. Le script
est écrit en Dart pur, sans dépendance, pour qu'il s'exécute dans la CI sans
résolution préalable — et pour qu'il reste lisible par ceux qui relisent le
dépôt.

**Conséquences.**
- Le fichier `.github/workflows/codeql.yml` est remplacé par
  `.github/workflows/security.yml`.
- `dart tools/osv_audit.dart` est exécutable seul, hors CI : c'est le même
  chemin de code que la vérification locale.
- Une dépendance vulnérable fait échouer la CI ; la correction est une
  montée de version, pas un contournement.
- L'audit porte sur les paquets publiés sur pub.dev : une dépendance tirée
  d'un dépôt git ou d'un chemin local n'existe pas dans le registre.

---

## D-36 — Les quatre services du lot 7 sont des ports optionnels

**Date** : 2026-10-26

**Décision.** Les formules et les quotas, la double authentification, les
équipes et le back-office sont quatre **ports** de l'API, présents dans
`AppDependencies` mais **facultatifs**. Le routeur n'enregistre les routes
correspondantes que si le port est câblé ; un serveur qui ne les câble pas ne
les sert pas, plutôt que de les servir en erreur.

La formule d'un compte se lit par **une seule** fonction, `PlanLookup`
(déclarée dans `db/plan_lookup.dart`) : les équipes et la double
authentification la reçoivent par injection et ne dépendent ni de la base des
formules ni du service de quota. Un compte sans formule est un compte
gratuit.

Les prix viennent du **domaine partagé** (`limpid_core`), pas de l'API :
`PlanDefinition.priceInCents` est l'unique source. Une formule inconnue est
**refusée** — la facturer au prix d'une autre serait une erreur de prix.

La preuve du second facteur voyage dans l'en-tête `X-Limpid-2FA`, et non
dans une claim du jeton : l'API n'émet pas les jetons, elle les vérifie. Le
contrôle est dans le middleware d'authentification, juste après la
vérification du jeton, et les routes `/v1/me/2fa` en sont exemptées : un
compte bloqué doit pouvoir s'inscrire.

**Pourquoi.** Les quatre services sont apparus en même temps, sur le même
paquet, avec quatre implémentations de persistance chacun. Un port facultatif
évite deux lisibles : soit on câblait tout et tout serveur de test devait
inventer quatre doubles, soit on ne câblait rien et le lot 7 n'existait pas.
La fonction de lecture unique évite le même piège pour la formule, qui est
partagée par trois services.

Le prix, lui, était déjà défini deux fois — dans le domaine et dans l'API —
et les deux copies ne disaient pas la même chose. Une source unique règle le
problème ; refuser une formule inconnue règle l'autre.

**Conséquences.**
- `AppDependencies` porte quatre ports facultatifs ; `production_dependencies`
  les construit pour PostgreSQL et SQLite, la suite de tests par des doubles
  en mémoire.
- Le middleware d'authentification reçoit un `TwoFactorGuard` facultatif :
  sans lui, aucune formule n'est exigée.
- Une formule Pro ou Studio **exige** la 2FA active : un test qui donne
  une telle formule à son compte doit aussi activer la double
  authentification. C'est le comportement voulu, pas un obstacle de test.
- Le back-office est une application distincte, servie sur un domaine
  distinct (maquette 18) : l'API n'expose que ses routes, sans écran.

---

## D-37 — Une formule payée vient d'un paiement, jamais d'une demande

**Date** : 2026-10-26

**Décision.** Trois règles, nées de la revue de code du lot 7.

1. **Une formule payée s'attribue avec une preuve de paiement.**
   `QuotaService.changePlan` refuse une formule payée sans référence de
   paiement. Le compte lui-même ne l'attribue pas : la voie légitime est
   `PUT /v1/admin/plans/:userId`, réservée à l'administrateur, qui porte la
   référence. C'est là que le webhook Stripe s'insérera. L'essai gratuit
   reste le chemin promotionnel : il ne demande pas de paiement.

2. **L'essai gratuit est unique par compte.** La colonne
   `trial_consumed_at` mémorise la consommation. Un compte qui a eu son
   essai ne peut pas en demander un second, même après être repassé sur la
   formule gratuite.

3. **Le second facteur se prouve partout, y compris dans le relais temps
   réel.** Le relais `/v1/sync` s'authentifie lui-même et échappait au
   contrôle. Il applique désormais le même garde que les routes HTTP, et la
   preuve voyage dans la chaîne de requête : un navigateur ne peut pas
   poser d'en-tête sur la poignée de main d'un WebSocket.

Deux jauges de D-15 sont vérifiées avant l'écriture : le nombre de projets
et le nombre de mots. La vérification d'un code TOTP a son propre seau, plus
serré que celui de l'API : un code ne compte que six chiffres.

**Pourquoi.** La route `POST /v1/me/plan` écrivait la formule demandée dans
la base sans vérifier ni paiement, ni droit acquis, ni rôle. Un compte
gratuit pouvait s'attribuer la formule Studio et la conserver. La route
écrivait même une entrée d'audit, qui donnait à l'opération une apparence
légitime — le genre de défaut qu'il faut corriger avant la mise en
production, pas après.

Le risque était d'autant plus réel que le chemin vers une formule payée
n'existait pas autrement : le webhook Stripe entrant n'est pas écrit, et la
seule porte d'entrée était celle du client. Le client était donc la seule
source de vérité — ce que la feuille de route interdit déjà : « les
webhooks reconstruct l'état, jamais le client ».

**Conséquences.**
- La colonne `trial_consumed_at` s'ajoute à `account_plans` (migration
  `0007`, jamais déployée).
- `PUT /v1/admin/plans/:userId` est la voie d'attribution d'une formule
  payée ; elle s'appuie sur la claim `role` du jeton vérifié.
- Le garde du second facteur est construit par les dépendances, pas par le
  serveur : le relais temps réel et les routes HTTP appliquent le même
  contrôle.
- La preuve du second facteur est lue dans l'en-tête `X-Limpid-2FA` **ou**
  dans le paramètre de requête `proof`.
- Le nombre de mots n'est recalculé que si le plafond de la formule est
  atteignable : reconstruire les documents d'un compte coûte plus cher que
  la limite ne vaut.
- La liste des migrations n'est plus écrite en dur dans le test : elle est
  lue depuis le répertoire, et ajouter une migration ne casse plus le test.

---

## D-38 — La garde de jetons de l'IA

**Date** : 2026-10-26

**Décision.** Le produit se vend en tokens d'IA : la page tarifaire vend
« IA standard, 500 k tokens / mois » et « IA premium · 2 M tokens / mois ».
Le domaine partagé décrit ce quota, le serveur compte les jetons réellement
consommés, et deux gardes les bornent.

### Les nombres, et d'où ils viennent

| Formule | Tokens / mois | Origine |
|---|---|---|
| Gratuit | aucun plafond | la page tarifaire n'annonce aucun quota de jetons pour la formule gratuite |
| Écrivain | 500 000 | maquette, page tarifaire : « IA standard, 500 k tokens / mois » |
| Pro | 2 000 000 | maquette, page tarifaire : « IA premium · 2 M tokens / mois » |
| Studio | 2 000 000 | maquette, page tarifaire : « Tout le plan Pro » |

Le Studio reprend donc l'allocation du Pro, en cycle annuel comme en cycle
mensuel : les jetons se comptent par mois, quel que soit le cycle de
facturation.

La formule gratuite ne vend pas de jetons : elle n'en plafonne pas. Sa
consommation d'IA reste encadrée par les deux réécritures quotidiennes
(D-15) et par la garde par requête. Son exposition au coût est donc
bornée — deux appels par jour, chacun sous le plafond d'un appel — et c'est
le point à surveiller le jour où le tarif des tokens sera connu. C'est une
décision écrite, pas un oubli : la stratégie de facturation à l'usage n'est
pas tranchée (D-25), et la formule gratuite pourra alors recevoir un
plafond lui aussi.

### Les deux gardes

1. **La garde par requête** est une **constante**, pas un quota de formule :
   16 000 tokens par appel, l'entrée estimée plus le plafond de sortie que
   la demande réclame (4 096 par défaut, le plafond de la fournisseur).
   Elle protège le budget du service d'un appel qui dérape — une invite
   devenue un chapitre collé par mégarde, une génération sans fin. Elle
   vaut pour toutes les formules : le quota de la formule borne le mois,
   ce plafond borne l'appel. C'est le coût **possible** de l'appel qui est
   mesuré, pas son coût probable : c'est ce coût-là que le budget doit
   couvrir.
2. **La garde par période** est le quota mensuel de la formule, compté par
   la mécanique existante : une fonctionnalité de quota à période mensuelle,
   le même compteur que les exports et les couvertures. Le compteur s'arrête
   au seuil atteint ; le dépassement éventuel est borné par la garde par
   requête.

Le « garde par jour » de D-08 n'est pas un troisième garde : il est porté
par la garde par requête et par le compteur de réécritures quotidiennes.

### Le compte

Le compte vient de la **fournisseur** quand elle le rapporte : l'API
Anthropic répond `usage.input_tokens` et `usage.output_tokens`, et la
passerelle additionne l'usage du flux. Ce compte est le seul exact, et
c'est lui qui est compté.

Quand la fournisseur ne dit rien — une passeuse de test, un fournisseur
local silencieux — le compte est **estimé**, et il est marqué comme une
estimation : `isTokenCountEstimated` dans l'événement de fin,
`tokens_estimated` dans la réponse, une trace dans le journal. Une
estimation qui se fait passer pour un relevé finit dans la facture de
l'auteur. Elle est comptée comme un usage quand même : c'est elle qui
protège le budget.

### La réponse

Une demande refusée est refusée **avant** l'appel à la fournisseur, en
`429 quota_exceeded`. Les détails portent la limite, la consommation, la
période et `reset_at` : le premier instant du mois suivant, en ISO 8601.
L'interface montre cette date à l'auteur, et un auteur qui ne sait pas
quand son quota revient écrit au support. La garde par requête n'a pas de
période — son budget est libéré dès que la demande est refusée — : elle
porte donc `reset_at` nul, et son message dit ce qu'il faut faire
(réduire la demande).

### Conséquences

- `PlanQuota.monthlyAiTokens` entre dans le domaine partagé, avec la
  valeur par défaut zéro : zéro veut dire « aucun plafond de jetons », et
  une description de quota construite avant la vente des jetons continue de
  compiler.
- `QuotaFeature.aiTokens` entre dans le catalogue du serveur : le
  compteur paraît dans l'instantané des quotas (`GET /v1/me/quota`) et
  l'allocation dans le catalogue public (`GET /v1/plans`).
- L'application ne montre pas encore la jauge des jetons : son écran lit
  trois compteurs, le quatrième attend son tour.
- La stratégie de facturation à l'usage reste ouverte (D-25) : ce lot
  **compte et plafonne**, il ne facture rien.



---

## D-39 — L'API publique ne demande pas la preuve du second facteur

**Date** : 2026-10-26

**Décision.** L'API publique (`/v1/api/`) s'authentifie par sa **clé
d'API**, pas par le jeton de session. Comme le préfixe est exempt du
middleware de session, il est exempt du contrôle du second facteur : une
clé d'API n'a pas à porter la preuve `X-Limpid-2FA`.

**Pourquoi.** La preuve du second facteur est attachée à une **session** :
elle est obtenue par l'écran, dans le contexte d'un compte connecté. Une
clé d'API est une **ressource** : elle se configure, se renouvelle, se
révoque, et sert depuis un serveur. Exiger la preuve sur cette surface
rendrait l'API inutilisable depuis un programme — il faudrait y porter une
session, ce qui n'est pas le modèle.

Les contrôles qui protègent cette surface sont ailleurs :

| Contrôle | Où il est |
|---|---|
| La clé n'est stockée que par empreinte SHA-256 | `api_key_service.dart` |
| Le secret n'est montré qu'une fois | la création et la rotation |
| La clé se renouvelle et se révoque | `POST /v1/api-keys/<id>/rotate`, `DELETE` |
| La formule Studio est exigée | `ApiAccessGuard`, sur **toutes** les routes |
| Chaque appel est journalisé | le journal d'audit, le limiteur de débit |

**Ce que la décision ne dit pas.** Le limiteur de débit se sert de l'adresse
du client pour l'API publique, là où il se sert du compte pour le reste :
une clé d'API n'est pas connue du limiteur avant d'être lue. C'est un
choix à revoir quand le volume le justifiera.

**Conséquences.** Un compte Studio dont la clé est volée donne accès à
l'API publique sans second facteur. Le remède est la révocation de la
clé, qui est immédiate et journalisée — pas un second facteur que le
programme n'a pas.

---

## D-40 — La clé d'idempotence du paiement vit dans une fenêtre de quinze minutes

**Date** : 2026-10-26

**Décision.** L'application envoie une clé `Idempotency-Key` à
`POST /v1/checkout`. La clé est tirée d'un **nonce** propre au dépôt, de
la formule, du cycle, et d'une **fenêtre de quinze minutes** : deux
commandes dans la même fenêtre partagent la même clé, et le serveur rejoue
la réponse de la première au lieu d'ouvrir une seconde session de
paiement.

**Pourquoi.** Le serveur sait déjà rejouer une commande (D-36, service
d'idempotence), mais l'application ne lui donnait pas de clé : un
double-clic sur « Payer » ouvrait **deux** sessions chez le prestataire de
paiement, et l'auteur pouvait payer deux fois.

La fenêtre est le compromis entre deux bornes :

| Fenêtre | Ce qu'elle donne | Ce qu'elle coûte |
|---|---|---|
| nulle | chaque clic ouvre une session | un double-clic paie deux fois |
| infinie | un clic paie toujours une fois | une session expirée est ressuscitée, et l'auteur ne peut plus commander |
| quinze minutes | un double-clic et une reprise immédiate sont absorbés | une commande vraiment nouvelle passe par une nouvelle clé |

La clé est **opaque** (le nonce) et **scopée au compte** par le serveur :
deux auteurs ne se gênent jamais, et personne ne peut deviner la clé
d'un autre.

**Ce que la décision ne dit pas.** Le serveur ne connaît pas l'intention
de l'auteur : il rejoue la réponse quand la clé et le corps sont les mêmes,
et refuse quand ils diffèrent (`409 idempotency_key_conflict`). Une
formule changée après une commande annulée produit donc une clé
différente — c'est voulu.

**Conséquences.** Un double-clic sur « Payer » ouvre une seule session.
Une commande reprise après quinze minutes ouvre une session neuve, même
si l'ancienne est encore ouverte : l'auteur peut avoir deux sessions
ouvertes chez le prestataire, mais il n'en paie qu'une — la formule du
compte est singularisée par le rappel de paiement.

---

## D-41 — Le secret de signature des rappels est stocké en clair, et l'URL de rappel est jugée deux fois

**Date** : 2026-10-26

**Décision.** Deux règles sur les points de rappel sortants.

1. Le **secret de signature** est stocké en clair dans la table
   `webhook_endpoints`. La **clé d'API**, elle, n'est stockée que par son
   empreinte SHA-256.
2. L'URL de rappel est jugée **deux fois** : à la déclaration (le schéma
   est `https`, l'hôte n'est pas privé) et **au moment de la livraison**
   (le nom est résolu, chaque adresse obtenue est jugée, et les
   redirections ne sont **jamais** suivies).

**Pourquoi.** Les deux secrets n'ont pas le même usage : une clé d'API
n'est que **vérifiée** — son empreinte suffit — alors qu'un secret de
signature doit **signer** la charge, donc être présent en clair au moment
de l'envoi. Le chiffrer au repos demanderait une clé que l'application
n'a pas aujourd'hui ; c'est un travail, pas une évidence.

L'URL, elle, est une **surface d'éjection** : le serveur y écrit la
charge de l'événement. La valider une seule fois, à la déclaration, ne
suffit pas : un nom public peut désigner une adresse interne
(`127.0.0.1.nip.io`), un enregistrement peut changer entre la déclaration
et la livraison, et un serveur de rappel peut **rediriger** vers une
adresse interne. La résolution se fait donc au moment d'écrire, et un
`303` transformerait sinon la livraison en lecture vers le réseau du
déploiement.

**Ce que la décision ne dit pas.** Le nom est résolu par le système : un
résolveur menteur (un `dns` qui renvoie une adresse publique puis, au
moment de la connexion, une adresse privée) passe entre les deux. La
 parade est la résolution au dernier moment, avant l'écriture — c'est ce
qui est fait — et non la garantie absolue.

**Conséquences.**

- Une fuite de la base expose les secrets de signature de tous les
  auteurs. Le remède est la **rotation** : chaque point de rappel porte
  un secret précédent, valable vingt-quatre heures, et l'endpoint se
  renouvelle. Une fuite n'est pas indolore, elle est bornée.
- Un rappel qui se résout vers une adresse interne est **refusé** à la
  livraison, et la livraison le dit : elle n'est pas une erreur muette.
- Les redirections ne sont pas suivies : un rappel doit viser l'adresse
  déclarée, pas celle vers laquelle son serveur nous enverrait.

## D-42 — La règle de dépendance est vérifiée par la CI, et l'éditeur a le droit d'utiliser le design system

**Date** : 2026-10-26

**Décision.** La règle de dépendance de PROMPT §5 est contrôlée par un
**script de la CI** (`tools/dependances.py`), et non par une règle de
l'analyseur. Deux corrections y sont inscrites :

1. `limpid_quill` (l'éditeur) a le droit d'importer
   `limpid_design_system` : l'éditeur **est** fait des widgets du design
   system, il n'a pas de theme propre ;
2. `limpid_api` a le droit d'importer `limpid_import` : la route d'import
   lit les six formats, c'est le lecteur qui les rend.

**Pourquoi.** L'invariant existe pour une raison précise : `limpid_core`
est partagé par le client Flutter et par le serveur Dart, donc il ne doit
jamais importer `package:flutter/*`. Tant que rien ne le contrôle, une
importation d'un jour suffit à rendre le paquet incompréhensible pour le
serveur — et l'échec n'apparaît qu'à la compilation du serveur, loin de
la faute.

Un paquet `custom_lint` aurait donné la règle **dans** l'analyseur, comme
l'écrit le critère. Le motif n'est pas dans le dépôt, et l'ajouter
demanderait de toucher aux `analysis_options.yaml` de tous les paquets —
donc de casser l'analyse de tout le monde pour un gain de forme. Le script
fait ce que la règle demande : **une violation échoue la CI**. La
difference — un script plutôt qu'une règle de l'analyseur — est notée
dans la feuille de route.

**Conséquences.**

- Le script lit les `import` et les `export` de chaque paquet, et ignore
  les commentaires : un paquet peut *parler* de `package:flutter/*` pour
  expliquer pourquoi il ne l'importe pas.
- Un paquet **pur Dart** (qui ne depend pas du SDK Flutter) ne peut pas
  importer `package:flutter/*` : le serveur n'a pas Flutter.
- La CI l'exécute à côté de la vérification des clés de traduction, et la
  vérification de vague l'exécute aussi.
