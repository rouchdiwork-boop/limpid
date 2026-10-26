"""Liste les fichiers source présents sur le disque mais absents de Git.

Un fichier source non versionné ne se voit pas : le poste compile, les tests
passent, et la CI échoue plus tard sur une cible que personne n'a vue. Le
motif `Icon?` du `.gitignore` a caché pendant des heures le fichier des
icônes du design system et les icônes de la PWA : ce script l'aurait dit
immédiatement.

    python tools/fichiers_non_suivis.py

Sort en code 1 dès qu'un fichier `.dart` du dépôt n'est pas suivi par Git.
Les fichiers générés (`.g.dart`, `.freezed.dart`, `l10n/generated/`) sont
ignorés : ils se reconstruisent.
"""

from __future__ import annotations

import os
import subprocess
import sys

# Répertoires dont le contenu n'est jamais versionné.
EXCLUDED_DIRECTORIES = {
    ".dart_tool",
    ".git",
    ".gradle",
    ".idea",
    ".limpid",
    ".vscode",
    "build",
    "node_modules",
}

# Fichiers produits par la chaîne d'outils, reconstruits à la demande.
GENERATED_MARKERS = ("generated", ".g.dart", ".freezed.dart")


def tracked_files() -> set[str]:
    """Renvoie l'ensemble des fichiers suivis par Git."""
    result = subprocess.run(
        ["git", "ls-files"], capture_output=True, text=True, check=True
    )
    return {line for line in result.stdout.split("\n") if line}


def untracked_sources(tracked: set[str]) -> list[str]:
    """Renvoie les fichiers `.dart` du disque qui ne sont pas suivis."""
    found: list[str] = []
    for root, directories, files in os.walk("."):
        directories[:] = [d for d in directories if d not in EXCLUDED_DIRECTORIES]
        for name in files:
            if not name.endswith(".dart"):
                continue
            path = os.path.relpath(os.path.join(root, name), ".").replace(
                os.sep, "/"
            )
            if path in tracked:
                continue
            if any(marker in path for marker in GENERATED_MARKERS):
                continue
            found.append(path)
    return sorted(found)


def main() -> int:
    """Signale les fichiers source absents de l'index."""
    missing = untracked_sources(tracked_files())
    if not missing:
        print("Tous les fichiers source sont versionnés.")
        return 0
    print(f"{len(missing)} fichier(s) source présent(s) sur le disque et non suivi(s) :")
    for path in missing:
        print(f"  {path}")
    print("\n`git check-ignore -v <chemin>` dit quelle règle lescache.")
    return 1


if __name__ == "__main__":
    sys.exit(main())
