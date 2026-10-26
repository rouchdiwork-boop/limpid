#!/usr/bin/env bash
# Vérification du monorepo Limpid : formatage, analyse statique et tests pour
# chaque paquet Dart ou Flutter présent. Sort en code 1 si un échec survient.
#
#   bash tools/verify.sh                  # tous les paquets
#   bash tools/verify.sh limpid_core      # un seul paquet
#   bash tools/verify.sh --no-test        # sans les tests
#
# Les paquets sont découverts dans `packages/` et `apps/`. La toolchain est
# déduite de la présence de « sdk: flutter » dans le pubspec.yaml : les
# paquets Flutter sont analysés et testés avec Flutter, les paquets Dart pur
# avec Dart.

set -uo pipefail
cd "$(dirname "$0")/.." || exit 1

RUN_TESTS=1
FILTER=""
for arg in "$@"; do
  case "$arg" in
    --no-test) RUN_TESTS=0 ;;
    *) FILTER="$arg" ;;
  esac
done

# ─── Découverte des paquets ────────────────────────────────────────────────
PACKAGES=()
for dir in packages/* apps/*; do
  [ -f "$dir/pubspec.yaml" ] || continue
  if [ -n "$FILTER" ] && [ "$(basename "$dir")" != "$FILTER" ]; then
    continue
  fi
  PACKAGES+=("$dir")
done

if [ "${#PACKAGES[@]}" -eq 0 ]; then
  echo "Aucun paquet à vérifier (filtre : « $FILTER »)."
  exit 1
fi

echo "Paquets détectés : ${#PACKAGES[@]}"
for pkg in "${PACKAGES[@]}"; do echo "  • $pkg"; done

FAILED=0
TOTAL_TESTS=0

for dir in "${PACKAGES[@]}"; do
  name=$(basename "$dir")
  echo ""
  echo "════════ $dir ════════"

  if grep -q "sdk: flutter" "$dir/pubspec.yaml" 2>/dev/null; then
    TOOL="flutter"
  else
    TOOL="dart"
  fi
  echo "• toolchain : $TOOL"

  if [ ! -d "$dir/.dart_tool" ]; then
    echo "• pub get"
    bash tools/avec_verrou.sh sh -c "cd \"$dir\" && $TOOL pub get" >/dev/null 2>&1 \
      || echo "  ! pub get a échoué (réseau ?)"
  fi

  # `flutter analyze` ne génère pas les localisations : sans ce passage, une
  # machine neuve échoue sur `package:limpid_app/l10n/generated/...`.
  if [ "$TOOL" = "flutter" ] && [ -f "$dir/l10n.yaml" ]; then
    echo "• gen-l10n"
    bash tools/avec_verrou.sh sh -c "cd \"$dir\" && flutter gen-l10n" >/dev/null 2>&1 \
      || echo "  ! gen-l10n a échoué"
  fi

  echo "• format"
  fmt_out=$(bash tools/avec_verrou.sh sh -c "cd \"$dir\" && dart format --output=none --set-exit-if-changed ." 2>&1)
  fmt_code=$?
  if [ "$fmt_code" -ne 0 ]; then
    echo "$fmt_out" | grep -E "Changed|Could not" | head -10 | sed 's/^/  ! /'
    FAILED=1
  else
    echo "  ✓ formaté"
  fi

  echo "• analyze"
  out=$(bash tools/avec_verrou.sh sh -c "cd \"$dir\" && $TOOL analyze --fatal-infos" 2>&1)
  if echo "$out" | grep -qi "no issues found"; then
    echo "  ✓ 0 erreur, 0 avertissement"
  else
    echo "$out" | tail -20
    FAILED=1
  fi

  if [ "$RUN_TESTS" -eq 0 ]; then
    echo "• test (ignoré)"
    continue
  fi

  echo "• test"
  if [ -d "$dir/test" ]; then
    out=$(bash tools/avec_verrou.sh sh -c "cd \"$dir\" && $TOOL test" 2>&1)
    echo "$out" | tail -3 | sed 's/^/  /'
    if echo "$out" | grep -qi "All tests passed"; then
      count=$(echo "$out" | grep -oE "\+[0-9]+" | tail -1 | tr -d '+')
      TOTAL_TESTS=$((TOTAL_TESTS + ${count:-0}))
    else
      FAILED=1
    fi
  else
    echo "  (aucun dossier test/)"
  fi
done

echo ""
echo "─────────────────────────────────────────"
echo "Tests exécutés : $TOTAL_TESTS"
if [ "$FAILED" -eq 0 ]; then
  echo "TOUT EST VERT"
else
  echo "ÉCHEC — voir les sections ci-dessus"
fi
exit "$FAILED"
