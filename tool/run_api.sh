#!/usr/bin/env bash
# Lancement de l'API Limpid en local (Dart Shelf, port configurable par PORT).
#
#   bash tool/run_api.sh
#
# Les variables d'environnement de la table ci-dessous sont lues par l'API au
# démarrage ; elles ne doivent jamais être écrites dans un fichier versionné.
#
#   LIMPID_DB_DRIVER          sqlite (défaut) ou postgres
#   LIMPID_DB_PATH            Chemin du fichier SQLite (.limpid/limpid.db)
#   DATABASE_URL              Connexion PostgreSQL managé (requis si postgres)
#   SUPABASE_URL              URL du projet Supabase Auth
#   SUPABASE_ANON_KEY         Clé publique Supabase Auth
#   SUPABASE_JWKS_URL         URL JWKS de validation des JWT
#   REDIS_URL                 Files d'attente et cache
#   R2_ENDPOINT               Point d'entrée Cloudflare R2
#   R2_ACCESS_KEY_ID          Identifiant R2
#   R2_SECRET_ACCESS_KEY      Secret R2
#   ANTHROPIC_API_KEY         Fournisseur IA par défaut
#   STRIPE_SECRET_KEY         Paiement et facturation
#   PORT                      Port d'écoute de l'API

set -uo pipefail
cd "$(dirname "$0")/.." || exit 1

API_DIR="apps/limpid_api"
ENTRY_POINT="bin/server.dart"

if [ ! -f "$API_DIR/pubspec.yaml" ]; then
  echo "L'API n'existe pas encore ($API_DIR est absent)."
  echo "Ce lot n'est pas démarré : voir docs/ROADMAP.md."
  exit 1
fi

if [ ! -d "$API_DIR/.dart_tool" ]; then
  echo "→ résolution des dépendances de l'API"
  (cd "$API_DIR" && dart pub get) || exit 1
fi

echo "→ démarrage de l'API"
cd "$API_DIR" || exit 1
exec dart run "$ENTRY_POINT" "$@"
