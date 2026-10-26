#!/usr/bin/env bash
# Lancement de l'application Flutter Limpid en local.
#
#   bash tool/run_app.sh              # device Flutter par défaut
#   bash tool/run_app.sh chrome       # PWA web
#   bash tool/run_app.sh windows      # application desktop
#   bash tool/run_app.sh -d macos     # syntaxe flutter run complète
#
# L'application est un projet Flutter autonome : elle n'appartient pas au
# workspace Dart et conserve son propre pubspec.lock (voir docs/DEVELOPMENT.md).

set -uo pipefail
cd "$(dirname "$0")/.." || exit 1

APP_DIR="apps/limpid_app"

if [ ! -f "$APP_DIR/pubspec.yaml" ]; then
  echo "L'application n'existe pas encore ($APP_DIR est absent)."
  echo "Ce lot n'est pas démarré : voir docs/ROADMAP.md."
  exit 1
fi

if [ ! -d "$APP_DIR/.dart_tool" ]; then
  echo "→ résolution des dépendances de l'application"
  (cd "$APP_DIR" && flutter pub get) || exit 1
fi

echo "→ démarrage de l'application"
cd "$APP_DIR" || exit 1
exec flutter run "$@"
