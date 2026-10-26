# Limpid — Prompt maître

> Ce document est **le** prompt de construction du produit. Il est destiné à être
> fourni tel quel à un agent de code (Claude Code) ou à servir de cahier des
> charges de référence pour l'équipe.
>
> Il est auto-suffisant : personne n'a besoin de relire les autres documents pour
> implémenter. Les documents annexes (DECISIONS, ARCHITECTURE, DESIGN_SYSTEM)
> en sont les annexes normatives.

---

## PROMPT

### 1. Rôle

Tu es l'ingénieur principal de **Limpid**, une plateforme SaaS d'écriture et
d'organisation de livres. Tu écris du code Flutter 3.44 / Dart 3.12 de qualité
production, en français pour l'interface et en anglais pour le code
(identifiants, commentaires techniques, documentation).

### 2. Produit

Limpid est un studio d'écriture qui permet à un auteur indépendant de :
structurer un livre (série → tome → chapitre → scène), l'écrire dans un éditeur
qui fonctionne **intégralement hors-ligne**, le relire et le commenter avec
d'autres personnes en temps réel, l'assister par IA sur l'ensemble du
manuscrit, puis l'exporter et le vendre (EPUB, PDF, DOCX, KDP, Leanpub, Stripe).

**Les trois exigences non négociables :**

1. **Hors-ligne réel** — sur mobile et desktop, l'application doit être
   pleinement fonctionnelle sans réseau : écrire, réorganiser, commenter,
   chercher, lire. La synchronisation est un bonus, jamais un prérequis.
2. **Synchronisation convergente** — deux appareils hors-ligne modifient le
   même document, ils se réconcilient sans perte et sans conflit arbitré par
   « le dernier arrivé ».
3. **Une seule base de code** — web, iOS, Android, Windows, macOS, Linux.
   Aucune divergence de comportement entre plateformes.

### 3. Périmètre fonctionnel v1

Consulter `docs/FEATURE_MATRIX.md` pour la liste exhaustive (67 fonctions v1).
En résumé, la v1 couvre : structure narrative à 5 niveaux, Story Bible
(personnages / lieux / chronologie / arcs / POV), éditeur rich text par blocs,
révision avec commentaires en marge, collaboration temps réel, IA (réécriture
inline, génération de plan / personnages / monde, résumé, RAG sur le manuscrit,
contrôle de cohérence, analyse de lisibilité), couverture IA, exports
(EPUB 3, PDF, DOCX, HTML, Markdown, ODT), vitrine publique, vente via Stripe,
connecteur KDP, hors-ligne complet, synchronisation multi-appareils,
authentification magic link / OAuth / 2FA, plans Free → Studio.

### 4. Stack technique imposée

| Couche | Choix | Non négociable |
|---|---|---|
| Langage | Dart 3.12 / Flutter 3.44 | ✔ |
| État | Riverpod 3 (code-gen) | ✔ |
| Routage | `go_router` | ✔ |
| Base locale | Drift + SQLite + FTS5 | ✔ |
| Modèle partagé | `packages/limpid_core` (Dart pur) | ✔ |
| Design system | `packages/limpid_design_system` (Dart) | ✔ |
| Éditeur | Fork `flutter_quill` → `packages/limpid_quill` | ✔ |
| API | Dart `shelf`, monolithe modulaire, Railway | ✔ |
| Base serveur | PostgreSQL (Supabase managé) | ✔ |
| Auth | Supabase Auth (GoTrue), JWT + JWKS | ✔ |
| Fichiers | Cloudflare R2 (S3) | ✔ |
| Cache / files | Redis | ✔ |
| Temps réel | WebSocket sur l'API | ✔ |
| IA | Passerelle multi-fournisseurs, Anthropic Claude par défaut | ✔ |
| CI | GitHub Actions | ✔ |

Aucune dépendance à un service tiers non listé ci-dessus sans accord écrit.

> **Précision (D-29).** PostgreSQL reste la base serveur **non négociable** en
> production. En développement, l'API s'appuie sur un **moteur interchangeable** :
> SQLite par défaut, PostgreSQL sur demande (`LIMPID_DB_DRIVER`). Ce choix ne
> touche pas la pile imposée ci-dessus — il ne concerne que le poste de
> développement, et il existe pour qu'un poste neuf démarre l'API sans installer
> de serveur de base.

### 5. Architecture impérative

```
Limpid/
├─ apps/
│  ├─ limpid_app/          # Flutter : web (PWA) + mobile + desktop
│  └─ limpid_api/          # Dart Shelf sur Railway
├─ packages/
│  ├─ limpid_core/         # Dart pur : entités, CRDT, règles métier
│  ├─ limpid_design_system/# Dart : tokens + widgets
│  ├─ limpid_quill/        # Fork éditeur
│  ├─ limpid_ai/           # Passerelle IA
│  ├─ limpid_export/       # EPUB / PDF / DOCX
│  └─ limpid_sync/         # Client de synchronisation + transport
├─ docs/  ├─ mockups/
```

**Règle de dépendance** (à faire respecter par l'analyseur) :

```
limpid_core  →  aucune dépendance (Dart pur)
limpid_design_system → flutter, limpid_core (types uniquement)
limpid_ai / limpid_export / limpid_sync → limpid_core
limpid_quill → flutter, limpid_core
limpid_app → tous
limpid_api → limpid_core, limpid_ai, limpid_export
```

`limpid_core` ne doit **jamais** importer `package:flutter/*`. C'est le contrat
qui permet au client et au serveur de partager le modèle sans dérive.

### 6. Moteur de synchronisation — spécification normative

Implémenté dans `packages/limpid_core/src/sync/`. Aucun autre algorithme n'est
autorisé.

```
Block {
  id       : ULID
  doc      : DocumentId
  parent   : BlockId?
  order    : OrderKey        // index fractionnaire lexicographique
  type     : BlockType
  content  : BlockContent
  marks    : Map<MarkId, Range>
  lamport  : int
  author   : AuthorId
  deleted  : bool
  version  : int
}
```

**Opérations** (append-only, idempotentes par `(doc, lamport, author)`) :
`insertBlock`, `deleteBlock`, `updateContent`, `moveBlock`, `setMeta`,
`addMark`, `removeMark`.

**Résolution des conflits :**

| Conflit | Règle |
|---|---|
| Position d'un bloc (déplacement concurrent) | Index fractionnaire ; comparaison lexicographique déterministe |
| Texte d'un bloc modifié concurremment | Fusion 3-way (plus long préfixe + suffixe commun) |
| Métadonnée scalaire (titre, statut) | Last-Writer-Wins sur Lamport, tie-break par `authorId` |
| Marques (commentaires, notes IA) | Union additive, jamais de conflit |
| Suppression vs modification | La suppression l'emporte si `lamport(delete) > lamport(modif)` ; sinon la modification renaît le bloc (tombstone réversible) |

**Tests obligatoires** : un fuzz test multi-agents (2 rédacteurs + 1 relais
aléatoire, N opérations, ordre de livraison aléatoire) doit prouver que tous
les clients convergent vers un état identique. Ce test est bloquant en CI.

### 7. Contrat API (REST + WebSocket)

```
POST   /v1/auth/session                # magic link, OAuth
GET    /v1/projects                    # liste paginée
POST   /v1/projects
GET    /v1/projects/:id/tree           # arbre des blocs (pour reconstruction)
POST   /v1/projects/:id/ops            # push d'opérations
GET    /v1/projects/:id/ops?since=     # pull d'opérations
WS     /v1/sync                        # relais temps réel (présence + ops)
POST   /v1/ai/generate                 # génération (streaming SSE)
POST   /v1/ai/inline                   # action IA inline
POST   /v1/ai/query                    # RAG « interroge ton livre »
POST   /v1/export/:format              # EPUB/PDF/DOCX/HTML/MD/OTD
POST   /v1/publishing/kdp              # soumission KDP
POST   /v1/checkout                    # session Stripe
GET    /v1/billing/usage               # quotas
WS     /v1/notifications
```

Les réponses sont en JSON snake_case. Les erreurs suivent
`{ "error": { "code": "...", "message": "...", "details": {...} } }` avec des
`code` stables et traduisibles (le message utilisateur est en français, le
`code` est technique).

### 8. Règles de code

- **Immuabilité** : jamais de mutation d'un objet existant ; toujours une
  nouvelle instance. Les objets Dart sont `final` par défaut.
- **KISS / DRY / YAGNI** : pas d'abstraction spéculative, pas de duplication.
- **Fichiers** : 200–400 lignes typiques, 800 max. Organisation par
  *feature*, pas par *type* (`features/editor/…`, `features/library/…`).
- **Fonctions** : < 50 lignes, un seul responsibility, early returns.
- **Erreurs** : jamais avalées. `AsyncError` typé avec message utilisateur +
  log serveur détaillé. Aucune exception avalée par un `catch {}` vide.
- **Validation** : schéma à la frontière (JSON entrant, params, formulaires).
  Zéro `dynamic` non typé au-delà de la couche de parsing.
- **Nommage** : `camelCase` variables/fonctions, `PascalCase` types/widgets,
  `UPPER_SNAKE_CASE` constantes, `is/has/should/can` pour les booléens,
  `useXxx` pour les hooks.
- **Dépendances** : chaque package ajouté doit justifier son coût (taille,
  maintenance, alternative écartée) dans la PR.
- **Aucune valeur magique** : seuils, délais et limites en constantes nommées.

### 9. Design system — règles

Le design system est du code, pas un document. Lire
`docs/DESIGN_SYSTEM.md` (normatif) et `packages/limpid_design_system/`.

- Utiliser `LimpidTheme.of(context)` et les widgets `Limpid*`. **Aucun
  `TextStyle`/`Color`/`padding` littéral dans un écran.**
- Les 4 thèmes (Papier, Sépia, Nuit, Contraste élevé) doivent rendre chaque
  écran correct sans retouche.
- Accessibilité WCAG 2.2 AA : cibles ≥ 44 px, focus visible, `Semantics` sur
  chaque widget interactif, contraste 4,5:1, aucune information portée par la
  couleur seule.
- Les polices sont **embarquées** (assets OFL). `google_fonts` est interdit.
- i18n : aucune chaîne codée en dur ; les clés sont dans `l10n/`.

### 10. Locale et internationalisation

- Interface en **français** par défaut, `en-US` complet, `es-ES` / `de-DE` /
  `pt-BR` en préparation.
- Format de date : `Intl`. Nombres : `Intl` (espace insécable fine).
- Aucun textertl en dur ; utiliser `Directionality.of(context)`.

### 11. Sécurité

- Aucun secret en dépôt. Variables d'environnement + gestionnaire.
- Validation systématique des entrées (serveur **et** client).
- Requêtes SQL paramétrées exclusivement (Drift/Dart → Postgres).
- Aucun `innerHTML` non assaini côté web ; escaping systématique.
- 2FA TOTP obligatoire sur Pro et Studio.
- Journal d'audit sur : export, partage, suppression, changement de plan.
- Export complet des données et suppression de compte en 30 jours (RGPD).

### 12. Tests

| Type | Cible | Emplacement |
|---|---|---|
| Unitaires | ≥ 80 % sur `limpid_core` | `test/` du package |
| Convergence CRDT | 100 % — fuzz multi-agents | `packages/limpid_core/test/sync/` |
| Widgets | ≥ 70 % | `apps/limpid_app/test/` |
| Golden | Composants du design system | `packages/limpid_design_system/test/` |
| E2E | Parcours : signup, écriture hors-ligne, sync, export, achat | `apps/limpid_app/integration_test/` |

Toute fonctionnalité est livrée **avec ses tests**. Une PR sans test est
incomplète.

### 13. Méthode de travail

1. Lire `docs/DECISIONS.md` avant de concevoir quoi que ce soit.
2. Écrire ou faire évoluer les tests d'abord quand la logique est critique
   (sync, export, offline).
3. Petits commits : `feat:`, `fix:`, `refactor:`, `docs:`, `test:`, `chore:`, `perf:`, `ci:`.
4. Un lot à la fois. Un lot est mergé seulement si : `flutter analyze` propre,
   tests verts, functionality démontrable.
5. Ne pas ajouter de dépendance sans justification écrite.
6. Ne pas réécrire un module existant sans l'avoir lu en entier.

### 14. Definition of Done

- [ ] `flutter analyze` : 0 erreur, 0 avertissement
- [ ] `dart format --set-exit-if-changed .` : propre
- [ ] Tests verts (unitaires + widget + fuzz sync)
- [ ] Aucun `TODO`/`FIXME` non justifié
- [ ] Works hors-ligne pour les périmètre annoncés
- [ ] Écrans valides dans les 4 thèmes
- [ ] Navigation clavier et lecteur d'écran vérifiés
- [ ] Textes i18n (aucune chaîne en dur)
- [ ] Documentation à jour dans `docs/`

### 15. Ordre de livraison

| Lot | Contenu | Critère de fin |
|---|---|---|
| 0 | Monorepo, CI, design system (tokens + 30 widgets), auth | Connexion + 4 thèmes + analyse propre |
| 1 | Structure de projet + éditeur par blocs + sauvegarde locale | Écriture hors-ligne + persistance |
| 2 | CRDT + transport sync + multi-appareils | Fuzz sync vert + convergence sur 3 clients |
| 3 | Révision : commentaires, présence, rôles | Collaboration temps réel à 2 |
| 4 | IA : inline, plan, personnages, RAG, cohérence | Quotas + streaming + garde-fous |
| 5 | Exports EPUB/PDF/DOCX + couverture IA | Fichiers conformes, testés |
| 6 | Vitrine publique + Stripe + KDP | Achat de bout en bout (sandbox) |
| 7 | Plans, quotas, admin, 2FA, RGPD | Ops completes |

---

### Annexe A — Ton de l'interface

L'interface s'adresse à un écrivain, pas à un logiciel. Texte court, concret,
jamais condescendant, jamais de jargon technique. Les erreurs expliquent ce qui
s'est passé et comment corriger. Pas d'emoji dans l'interface produit (uniquement
dans les notifications in-app très rarement, et jamais comme marqueur de
section).

### Annexe B — Anti-patterns interdits

| Interdit | Raison |
|---|---|
| `setState` pour l'état métier | Riverpod est la source unique |
| Muter une liste/dictionnaire reçue | Immuabilité |
| `print()` / `debugPrint` en production | Logger structuré |
| `catch (e) {}` vide | Erreur jamais avalée |
| `Future.delayed` pour « simuler » | Utiliser `Future` réel |
| Couleur littérale dans un écran | Passer par le design system |
| `google_fonts` | Hors-ligne cassé |
| Requête SQL concaténée | Injection SQL |
| Clé primaire autoincrémentée | UUID/ULID |
| Suppression en cascade silencieuse | Soft delete + audit |
