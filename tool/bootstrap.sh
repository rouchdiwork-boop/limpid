#!/usr/bin/env bash
# Installation des dépendances de tous les paquets du monorepo Limpid.
#
#   bash tool/bootstrap.sh              # tous les paquets présents
#   bash tool/bootstrap.sh limpid_core  # un seul paquet
#
# Équivalent de `melos bootstrap` pour les environnements où melos n'est pas
# installé. Les paquets absents du dépôt sont ignorés : le monorepo est
# vérifiable dans tous ses états intermédiaires.
#
# Les dépendances de chemin entre paquets sont résolues localement : chaque
# paquet est résolu depuis son propre dossier, ce qui correspond exactement à
# ce que fait `melos bootstrap` avec usePubspecOverrides.

set -uo pipefail
cd "$(dirname "$0")/.." || exit 1

MEMBERS=()
if [ $# -gt 0 ]; then
  for pkg in "$@"; do
    for dir in "packages/$pkg" "apps/$pkg"; do
      [ -f "$dir/pubspec.yaml" ] && MEMBERS+=("$dir")
    done
  done
else
  for dir in packages/* apps/*; do
    [ -f "$dir/pubspec.yaml" ] && MEMBERS+=("$dir")
  done
fi

if [ ${#MEMBERS[@]} -eq 0 ]; then
  echo "Aucun paquet trouvé dans packages/ ni apps/."
  exit 0
fi

FAILED=0

for dir in "${MEMBERS[@]}"; do
  pkg=$(basename "$dir")
  if grep -q "sdk: flutter" "$dir/pubspec.yaml" 2>/dev/null; then
    TOOL="flutter"
  else
    TOOL="dart"
  fi

  echo "→ $pkg ($TOOL pub get)"
  if ! (cd "$dir" && $TOOL pub get); then
    echo "  ! échec de $TOOL pub get pour $pkg"
    FAILED=1
  fi
done

echo ""
if [ "$FAILED" -eq 0 ]; then
  echo "Dépendances installées."
else
  echo "ÉCHEC — certaines dépendances n'ont pas pu être installées."
fi
exit "$FAILED"
