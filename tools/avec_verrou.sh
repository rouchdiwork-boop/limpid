#!/usr/bin/env bash
# Exécute une commande sous le verrou de compilation du monorepo.
#
# La machine n'a que 7,3 Go de RAM : une seule compilation Dart à la fois.
# Le verrou est un répertoire — `mkdir` est atomique sur Windows, c'est le
# seul mutex fiable ici.
#
#   bash tools/avec_verrou.sh dart analyze --fatal-infos
#   bash tools/avec_verrou.sh sh -c 'cd apps/limpid_api && dart test'
#
# Le verrou est relâché à la fin, même si la commande échoue. Un verrou laissé
# par un processus mort est détecté et libéré : le répertoire vide et l'absence
# de processus Dart signifient que le verrou est périmé.

set -uo pipefail
cd "$(dirname "$0")/.." || exit 1

LOCK_DIR=".limpid/dart.lock"
STALE_AFTER_SECONDS=300
WAIT_SECONDS=5

# Le temps écoulé depuis la dernière modification du verrou.
lock_age() {
  local now
  now=$(date +%s)
  local modified
  modified=$(stat -c %Y "$LOCK_DIR" 2>/dev/null || echo 0)
  echo $((now - modified))
}

# Un compilation Dart tourne-t-elle encore ?
dart_running() {
  if command -v tasklist >/dev/null 2>&1; then
    tasklist //FI "IMAGENAME eq dart.exe" //NH 2>/dev/null | grep -qi dart && return 0
    tasklist //FI "IMAGENAME eq dartaotruntime.exe" //NH 2>/dev/null | grep -qi dart && return 0
    return 1
  fi
  pgrep -f "dart-sdk/bin/dart" >/dev/null 2>&1
}

acquire() {
  while ! mkdir "$LOCK_DIR" 2>/dev/null; do
    if [ "$(lock_age)" -gt "$STALE_AFTER_SECONDS" ] && ! dart_running; then
      echo "verrou périmé (plus de $STALE_AFTER_SECONDS s, aucun Dart actif) : libéré" >&2
      rmdir "$LOCK_DIR" 2>/dev/null
      continue
    fi
    sleep "$WAIT_SECONDS"
  done
}

release() {
  rmdir "$LOCK_DIR" 2>/dev/null
}

acquire
trap release EXIT INT TERM

"$@"
STATUS=$?
release
trap - EXIT INT TERM
exit "$STATUS"
