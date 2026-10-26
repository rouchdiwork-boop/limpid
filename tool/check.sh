#!/usr/bin/env bash
# Vérification complète du monorepo Limpid : formatage, analyse statique et
# tests, paquet par paquet.
#
#   bash tool/check.sh              # tous les paquets présents
#   bash tool/check.sh limpid_core  # un seul paquet
#
# Ce script est un simple relais vers tools/verify.sh, qui porte la logique de
# vérification. L'équivalent PowerShell est tool/check.ps1.

set -uo pipefail
cd "$(dirname "$0")/.." || exit 1
exec bash tools/verify.sh "$@"
