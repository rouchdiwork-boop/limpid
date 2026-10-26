# Limpid — Guide de développement

Ce document décrit l'outillage du monorepo, les commandes de travail
quotidiennes et les décisions de configuration prises pour le workspace.

Le `README.md` décrit le produit et l'architecture. Ce document décrit **comment
on travaille dans le dépôt**.

---

## 1. Prérequis

| Outil | Version | Rôle |
|---|---|---|
| Flutter | 3.44.4 | Application cliente, design system, éditeur |
| Dart | 3.12.2 | API, paquets purs, outillage |
| melos | 6.3.x | Orchestration du monorepo (optionnel) |
| Git | 2.40+ | Versionnement |

Flutter et Dart doivent être sur le `PATH` :

```bash
flutter --version   # Flutter 3.44.4 • Dart 3.12.2
dart --version      # Dart SDK version: 3.12.2
```

melos est **déclaré comme dépendance de développement de la racine** : il
suffit de résoudre la racine pour l'utiliser, sans installation globale.

```bash
dart pub get          # à la racine : installe melos
dart run melos list   # melos est utilisable immédiatement
```

Les scripts de `melos.yaml` appellent d'ailleurs `dart run melos` et non
l'exécutable `melos` : aucune installation globale n'est nécessaire et la
version employée est celle verrouillée par le dépôt.

> **Pourquoi melos 6 et pas melos 8 ?** Melos 7 et suivants ont supprimé le
> fichier `melos.yaml` : la configuration vit désormais dans la section
> `melos:` du `pubspec.yaml` racine, et melos **exige** que tous les paquets
> appartiennent au workspace Dart (`resolution: workspace`). Cette migration
> n'est pas encore faite (voir § 6). Melos 6 lit `melos.yaml` et résout chaque
> paquet indépendamment, ce qui correspond à l'état actuel du dépôt.

---

## 2. Installation

### 2.1 Avec melos (recommandé)

```bash
dart pub get          # à la racine : résout melos
dart run melos bootstrap
```

`melos bootstrap` résout les dépendances de chaque paquet et écrit un
`pubspec_overrides.yaml` dans les paquets qui dépendent d'un autre paquet du
monorepo : les dépendances de chemin sont ainsi toujours résolues localement.

### 2.2 Sans melos

```bash
bash tool/bootstrap.sh          # Git Bash, Linux, macOS
powershell -File tool/bootstrap.ps1   # Windows PowerShell
```

Les deux scripts font la même chose : ils parcourent `packages/` et `apps/`,
ignorent les répertoires sans `pubspec.yaml` et lancent `pub get` avec la
toolchain adaptée (`flutter pub get` pour un paquet Flutter, `dart pub get`
pour un paquet pur).

---

## 3. Lancer l'application et l'API

### 3.1 Application Flutter

```bash
bash tool/run_app.sh              # device Flutter par défaut
bash tool/run_app.sh chrome       # PWA web
bash tool/run_app.sh windows      # application desktop
```

L'application est un projet Flutter autonome : elle **n'appartient pas** au
workspace Dart et conserve son propre `pubspec.lock` (voir § 6.2).

Elle suit trois couches, séparées par le dossier (D-31) :

| Couche | Dossier | Contenu |
|---|---|---|
| Contrat | `lib/src/domain/` | Les interfaces de persistance et l'enum `SyncStatus` |
| Implémentation | `lib/src/data/` | La base SQLite locale, le client HTTP, la synchronisation |
| Écrans | `lib/src/features/` | Un dossier par fonctionnalité |

Le point de composition — l'endroit où les implémentations sont fournies aux
contrats — est unique : `lib/src/app/dependencies.dart`. Un écran ne dépend
**que** des interfaces : il se teste donc avec un dépôt factice, sans base de
données et sans réseau.

### 3.2 API Dart

```bash
bash tool/run_api.sh
```

**Aucun service externe n'est requis.** L'API démarre par défaut sur un fichier
SQLite local et applique ses migrations au lancement (D-29) :

```bash
LIMPID_DB_DRIVER=sqlite LIMPID_DB_PATH=.limpid/limpid.db bash tool/run_api.sh
```

Pour travailler contre PostgreSQL (production, ou validation du dialecte) :

```bash
LIMPID_DB_DRIVER=postgres DATABASE_URL=postgres://... bash tool/run_api.sh
```

Variables d'environnement attendues au démarrage :

| Variable | Rôle |
|---|---|
| `LIMPID_DB_DRIVER` | `sqlite` (défaut) ou `postgres` |
| `LIMPID_DB_PATH` | Chemin du fichier SQLite, défaut `.limpid/limpid.db` |
| `DATABASE_URL` | Connexion PostgreSQL managé — **requis si `LIMPID_DB_DRIVER=postgres`** |
| `SUPABASE_URL`, `SUPABASE_ANON_KEY`, `SUPABASE_JWKS_URL` | Supabase Auth et validation des jetons |
| `REDIS_URL` | Files d'attente et cache |
| `R2_ENDPOINT`, `R2_ACCESS_KEY_ID`, `R2_SECRET_ACCESS_KEY` | Stockage des fichiers |
| `ANTHROPIC_API_KEY` | Fournisseur IA par défaut |
| `STRIPE_SECRET_KEY` | Paiement et facturation |
| `PORT` | Port d'écoute de l'API |

Aucun secret n'est versionné. Un fichier `.env` local est ignoré par git ;
`apps/limpid_api/.env.example` documente les clés attendues.

Les migrations existent en deux dialectes et doivent rester équivalents :

| Dossier | Dialecte | Usage |
|---|---|---|
| `apps/limpid_api/db/migrations/` | PostgreSQL | Production, Supabase |
| `apps/limpid_api/db/migrations/sqlite/` | SQLite | Développement local |

---

## 4. Chaîne de vérification

### 4.1 Tout le monorepo

```bash
dart run melos run ci
```

ou, sans melos :

```bash
bash tool/check.sh
powershell -File tool/check.ps1
```

Les deux sont des relais vers `tools/verify.sh` et son équivalent PowerShell,
qui enchaînent pour chaque paquet présent :

1. `flutter gen-l10n` si le paquet a un `l10n.yaml` — `flutter analyze` ne
   génère pas les localisations, une machine neuve échouerait sans ce
   passage ;
2. `dart format --output=none --set-exit-if-changed .` ;
3. `dart analyze --fatal-infos` (ou `flutter analyze`) ;
4. `dart test` (ou `flutter test`).

Les paquets absents du dépôt sont ignorés proprement : le monorepo reste
vérifiable pendant la construction des applications.

### 4.2 Un seul paquet

```bash
cd packages/limpid_core
dart analyze
dart test
```

Le fuzz de convergence du CRDT est bloquant et se lance seul :

```bash
dart test packages/limpid_core/test/sync/
```

### 4.3 Scripts melos

| Script | Rôle |
|---|---|
| `dart run melos run bootstrap` | Résout les dépendances de tous les paquets |
| `dart run melos run analyze` | Analyse statique, `--fatal-infos` et `--fatal-warnings` |
| `dart run melos run test` | Tests unitaires de tous les paquets |
| `dart run melos run test:ci` | Tests unitaires, sans concurrence, échec au premier paquet cassé |
| `dart run melos run format` | Formatage des sources Dart |
| `dart run melos run format:check` | Échoue si une source n'est pas formatée |
| `dart run melos run build:web` | Build web de l'application |
| `dart run melos run build:desktop` | Build desktop de l'application |
| `dart run melos run build:android` | Build Android de l'application |
| `dart run melos run build:ios` | Build iOS de l'application |
| `dart run melos run ci` | Chaîne complète : format, analyse, tests |

---

## 5. Intégration continue

`.github/workflows/ci.yml` suit D-21 :

```
analyze → test → build web → build desktop → build Android → déploiement Railway
```

| Job | Déclencheur | Rôle |
|---|---|---|
| `discover` | Toujours | Liste les paquets présents dans le dépôt |
| `analyze` | Toujours | `pub get`, `analyze --fatal-infos`, `format --set-exit-if-changed` |
| `test` | Toujours | `dart test` ou `flutter test` selon le paquet, avec délai d'expiration |
| `build-web` | `push` | `flutter build web --release` |
| `preview-web` | `pull_request` | Preview web de la pull request |
| `build-desktop` | Tag `v*` | Build desktop |
| `build-android` | Tag `v*` | Build Android |
| `deploy-api` | `push` sur `main` | Déploiement Railway |

Les jobs de build et de déploiement **vérifient l'existence de l'application
avant de s'exécuter** : tant que `apps/limpid_app` et `apps/limpid_api`
n'existent pas, la CI reste verte.

Les secrets de déploiement (`RAILWAY_TOKEN`, `RAILWAY_PROJECT_ID`,
`RAILWAY_SERVICE`, `SUPABASE_ACCESS_TOKEN`, `DATABASE_URL`) ne sont lus que
par le job `deploy-api`, jamais par les autres, et jamais en clair.

Les permissions de la CI sont minimales (`contents: read`), et un nouveau run
annule le précédent sur la même branche.

---

## 6. Décisions de configuration du workspace

### 6.1 Pourquoi les paquets sont résolus paquet par paquet

Dart 3.6+ propose les *pub workspaces* : le paquet racine liste ses membres
sous `workspace:`, chaque membre accepte avec `resolution: workspace` dans son
propre `pubspec.yaml`, et pub résout alors l'ensemble depuis la racine avec un
`pubspec.lock` unique.

**Le workspace n'est pas encore activé, et c'est délibéré.** Deux faits
mesurés sur Dart 3.12.2 et Flutter 3.44.4 :

1. `pub` **refuse** un membre listé dans `workspace:` qui n'a pas
   `resolution: workspace` :

   ```
   packages\limpid_core\pubspec.yaml is included in the workspace from
   .\pubspec.yaml, but does not have `resolution: workspace`.
   ```

   `dart pub get` à la racine échoue alors, et le `pubspec.lock` du paquet est
   supprimé dès qu'il accepte (`Deleting old lock-file: ...`).

2. Les paquets `limpid_core`, `limpid_design_system`, `limpid_ai` et
   `limpid_export` **possèdent déjà leur `pubspec.lock` et sont testés contre
   lui**. Les faire accepter le workspace supprimerait ce verrou et
   re-résoudrait le monorepo entier : l'état testé des paquets serait
   modifié.

Tant que la migration n'a pas eu lieu, la résolution se fait donc **paquet par
paquet**, ce qui est exactement ce que font `melos bootstrap` et
`tool/bootstrap.sh`. Les deux donnent le même résultat : chaque paquet garde
son propre verrou et ses versions testées.

La liste cible du workspace est écrite dans le `pubspec.yaml` racine, en
commentaire, et dans `melos.yaml` (liste `packages:`), qui est la
configuration du workspace utilisée par l'outillage.

### 6.2 Pourquoi `apps/limpid_app` est exclu du workspace Dart

**Dart 3.12 autorise en réalité une application Flutter dans un workspace** —
contrairement à ce que l'on suppose souvent. Vérifié expérimentalement avec
Flutter 3.44.4 : `flutter pub get` à la racine fonctionne, `flutter build web`
et `flutter test` lancés depuis le dossier de l'application fonctionnent aussi.

L'application est néanmoins **exclue**, pour une raison qui n'est pas technique
mais contractuelle :

- une application publie des artefacts reproductibles. Son `pubspec.lock` doit
  être versionné pour que le build released corresponde exactement à ce qui a
  été testé ;
- dans un workspace, il n'y a qu'un seul verrou, à la racine, et `pub`
  supprime le verrou de chaque membre. Le verrou de l'application
  disparaîtrait, et il serait remplacé par un verrou partagé avec les six
  paquets de bibliothèque ;
- le verrou de l'application serait alors lié à la dépendance de version des
  bibliothèques : une mise à jour de `limpid_export` modifierait les entrées
  du build web, mobile et desktop.

L'application reste un membre à part entière du monorepo : melos la liste
dans `melos.yaml`, la CI la construit et la teste, et `tool/run_app.sh` la
lance. Seule sa résolution de dépendances lui reste propre.

Le même raisonnement s'applique à `apps/limpid_api`, qui est une application
serveur : son verrou est versionné et il reste hors du workspace pour la
même raison. La liste cible du workspace contient donc les six paquets de
bibliothèque et l'API, mais pas l'application Flutter.

### 6.3 Sort des `pubspec.lock`

La règle Dart est simple : **une bibliothèque ne versionne pas son verrou, une
application le versionne.**

| Chemin | Règle appliquée | Raison |
|---|---|---|
| `packages/*/pubspec.lock` | Ignoré, sauf exception | Bibliothèque : le verrou n'engage pas le consommateur |
| `packages/limpid_core/pubspec.lock` | **Versionné** (exception) | Verrou testé, à ne pas supprimer avant la migration |
| `packages/limpid_design_system/pubspec.lock` | **Versionné** (exception) | idem |
| `packages/limpid_ai/pubspec.lock` | **Versionné** (exception) | idem |
| `packages/limpid_export/pubspec.lock` | **Versionné** (exception) | idem |
| `apps/limpid_app/pubspec.lock` | **Versionné** | Application : build reproductible |
| `apps/limpid_api/pubspec.lock` | **Versionné** | Application : build reproductible |
| `pubspec.lock` (racine) | Ignoré | Racine : outillage, pas d'artefact publié |

Les quatre exceptions sont temporaires : elles disparaissent quand ces
paquets rejoignent le workspace Dart, le verrou unique de la racine prenant le
relais. Elles sont listées explicitement dans `.gitignore` pour que la
migration soit visible dans une seule revue.

### 6.4 Recette de migration vers le workspace Dart

Une seule pull request par paquet, dans cet ordre, pour ne jamais casser un
paquet déjà testé :

1. **Pour un paquet** — ajouter `resolution: workspace` dans son
   `pubspec.yaml`, à côté de `environment:` :

   ```yaml
   environment:
     sdk: ^3.12.0

   resolution: workspace
   ```

2. **Pour la racine** — décommenter le bloc `workspace:` du `pubspec.yaml`
   racine et y ajouter le paquet concerné.

3. **Résoudre et vérifier** :

   ```bash
   dart pub get          # à la racine : un seul lock pour tout le workspace
   bash tool/check.sh    # le paquet doit rester vert
   ```

4. **Supprimer l'exception** correspondante dans `.gitignore` une fois le
   verrou du paquet supprimé par pub.

⚠️ **Attention** : l'étape 1 supprime le `pubspec.lock` du paquet et re-résout
le workspace entier. Ne la faire que sur un paquet dont les tests sont verts,
et dans une pull request dédiée.

Quand les huit membres ont accepté, on peut passer à melos 7 ou 8 : la
configuration `melos.yaml` bascule dans la section `melos:` du
`pubspec.yaml` racine, et `usePubspecOverrides` disparaît (melos 7+ écrit
toujours les `pubspec_overrides.yaml`).

### 6.5 Configuration d'analyse partagée

Le `analysis_options.yaml` racine est volontairement **minimal** :

```yaml
include: package:lints/recommended.yaml

analyzer:
  language:
    strict-casts: true
    strict-raw-types: true
  errors:
    todo: ignore
```

Chaque paquet possède sa propre configuration, qui **prime** sur celle de la
racine. Le fichier racine ne s'applique donc qu'aux sources Dart qui ne sont
dans aucun paquet et aux paquets qui n'ont pas encore de configuration.

C'est le cas de `packages/limpid_quill` : tant qu'il ne déclare pas son propre
`analysis_options.yaml`, il hérite de celui de la racine. La configuration
racine a été choisie pour n'introduire **aucun** diagnostic supplémentaire
dans ce paquet : le test A/B (analyse avec et sans le fichier racine) ne montre
aucun écart. Les règles strictes restent dans les paquets, là où elles peuvent
être relues avec le code qu'elles encadrent.

### 6.6 Normalisation des fins de ligne

Le dépôt est normalisé en LF (`\n`), y compris sur Windows. Deux mécanismes
se complètent :

- `.gitattributes` impose `eol=lf` pour les fichiers texte ;
- la configuration du dépôt git force `core.autocrlf=false` et
  `core.safecrlf=false`, pour que les fichiers soient stockés tels qu'ils sont
  écrits.

---

## 7. Stratégie de branches

| Branche | Usage | Durée |
|---|---|---|
| `main` |état stable de l'application, toujours déployable | — |
| `feat/<lot>-<sujet>` | Une fonctionnalité du lot en cours | La durée du lot |
| `fix/<sujet>` | Correction de bug | Courte |
| `chore/<sujet>` | Outillage, documentation, CI | Courte |
| `docs/<sujet>` | Documentation seule | Courte |

Règles :

- `main` n'est **jamais** réécrite : pas de `rebase` ni de `force push` sur
  une branche déjà publiée.
- Une branche vit le temps d'un lot (docs/PROMPT.md, § 15). Les commits sont
  petits et frequentés, jamais un commit de plusieurs jours.
- Une pull request est ouverte **dès qu'une fonctionnalité est démontrable**,
  pas seulement à la fin du lot : le lot 0 compte 12 pull requests.
- Une pull request ne part que si la CI est verte et si la Definition of Done
  (docs/PROMPT.md, § 14) est cochée.
- Les décisions d'architecture sont écrites dans `docs/DECISIONS.md` avant
  d'être codées, jamais après.

### Convention des commits

```text
<type>: <description>
```

Types : `feat`, `fix`, `refactor`, `docs`, `test`, `chore`, `perf`, `ci`.

Exemples :

```text
feat: add the fractional index rebalancing to the CRDT
fix: converge the tombstone when a delete arrives after a move
docs: record the workspace migration recipe
ci: run the fuzz test on every pull request
```

Le corps du message explique **pourquoi**, pas **quoi** : le diff montre déjà
le quoi.

---

## 8. Ce qu'il ne faut pas faire

| Interdit | Raison |
|---|---|
| Commiter un secret | Les secrets sont des variables d'environnement |
| Modifier un `analysis_options.yaml` de paquet sans relire le code du paquet | Une règle stricte peut casser un paquet déjà vert |
| Supprimer un `pubspec.lock` d'un paquet testé | C'est l'état contre lequel les tests sont verts |
| `git commit -a` | Les fichiers non suivis (« ?? ») sont des fichiers nouveaux qui demandent une décision |
| Contourner la CI (`--no-verify`) | La CI est la définition de la qualité |
| Écrire du code applicatif dans le paquet racine | La racine ne contient que de l'outillage |
| Toucher à `packages/` ou `apps/` depuis une pull request d'outillage | Ces répertoires ont des règles de dépendance propres (PROMPT.md, § 5) |
| Lancer deux compilations Dart en même temps sur le poste | Le poste de développement a 7,3 Go de RAM : un `flutter test` occupe environ 450 Mo, et deux compilations simultanées suffisent à le maintenir à zéro Mo libre — plus aucun processus ne démarre alors. Quand plusieurs agents travaillent, un seul compile à la fois, les autres attendent |
