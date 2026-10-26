# limpid_api

L'API Limpid : monolithe modulaire `shelf`, sans état, déployé sur Railway.
Elle ne dépend jamais de Flutter : le domaine et le CRDT viennent de
`packages/limpid_core`, la passerelle IA de `packages/limpid_ai`, le moteur
d'export de `packages/limpid_export`.

## Lancer

```bash
dart pub get
dart run bin/server.dart
```

**Aucune variable d'environnement n'est nécessaire.** Par défaut l'API :

- écrit dans un fichier SQLite local (`.limpid/limpid.db`) ;
- applique ses migrations au démarrage ;
- démarre en profil `dev`, où les services distants (Supabase, R2, Redis,
  Anthropic, Stripe) sont facultatifs et remplacés par des implémentations
  qui refusent l'appel avec une erreur propre.

Le serveur expose alors `/health` et répond `401` aux routes protégées.

## Variables d'environnement

| Variable | Rôle |
|---|---|
| `LIMPID_PROFILE` | `dev` (défaut) ou `prod` — en `prod`, toute variable manquante empêche le démarrage |
| `LIMPID_DB_DRIVER` | `sqlite` (défaut) ou `postgres` |
| `LIMPID_DB_PATH` | Chemin du fichier SQLite, défaut `.limpid/limpid.db` |
| `DATABASE_URL` | Connexion PostgreSQL — **requis si `LIMPID_DB_DRIVER=postgres`** |
| `SUPABASE_URL`, `SUPABASE_ANON_KEY`, `SUPABASE_JWKS_URL` | Supabase Auth et validation des jetons |
| `REDIS_URL` | Files d'attente et cache |
| `R2_ACCOUNT_ID`, `R2_ENDPOINT`, `R2_ACCESS_KEY_ID`, `R2_SECRET_ACCESS_KEY`, `R2_BUCKET` | Stockage des fichiers |
| `ANTHROPIC_API_KEY` | Fournisseur IA |
| `STRIPE_SECRET_KEY` | Paiement |
| `PORT` | Port d'écoute, défaut `8080` |

Le fichier `.env.example` documente les mêmes clés avec leurs valeurs par
défaut.

## Persistance

L'API ne parle jamais directement à un moteur SQL. Trois implémentations
existent derrière les mêmes interfaces (`ProjectStore`, `SyncStore`,
`AuditLog`) :

| Implémentation | Usage |
|---|---|
| `PostgresProjectStore` et al. | Production (Supabase managé) |
| `SqliteProjectStore` et al. | Développement par défaut (D-29) |
| `InMemoryProjectStore` et al. | Tests unitaires |

Les migrations sont doublées par dialecte et doivent rester équivalentes :
`db/migrations/` (PostgreSQL) et `db/migrations/sqlite/` (SQLite). La CI
compare les deux schémas table par table et colonne par colonne.

Les scénarios de dépôt sont écrits une seule fois, dans
`test/helpers/project_store_contract.dart` et ses voisines, et exécutés
contre **chaque** implémentation. Un test qui ne passe que sur l'un des deux
moteurs est un bug.

## Structure

```
bin/server.dart              Point d'entrée : configuration, serveur, arrêt
db/migrations/               Migrations PostgreSQL
db/migrations/sqlite/        Migrations SQLite
lib/src/
├── auth/                    Validation des jetons Supabase
├── config/                  Configuration lue dans l'environnement
├── db/                      Ports de persistance et leurs adaptateurs
├── errors/                  Erreurs typées et format de la réponse
├── http/                    Réponses, corps JSON, pagination par curseur
├── logging/                 Journal structuré
├── middleware/              CORS, quotas, délai, journalisation
├── redis/                   Cache et files d'attente
├── routes/                  Routage HTTP et WebSocket
├── services/                Accès, IA, paiement, idempotence
├── storage/                 Stockage objet (R2) et signature V4
└── sync/                    Protocole de synchronisation et arbre du projet
test/
├── helpers/                 Contrats de dépôt, serveur de test, clés
└── *_test.dart              Scénarios par domaine
```

## Vérification

```bash
dart analyze --fatal-infos   # 0 erreur, 0 avertissement
dart test                    # 182 tests
dart format --set-exit-if-changed .
```

Pour vérifier le chemin PostgreSQL sur une machine qui l'a :

```bash
dart run tool/postgres_check.dart postgres://utilisateur:mot_de_passe@hote:5432/limpid
```
