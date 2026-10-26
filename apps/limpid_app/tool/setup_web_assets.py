"""Copie les fichiers WebAssembly nécessaires à la base locale sur le web.

Drift ne peut pas ouvrir une base SQLite dans un navigateur sans deux
fichiers servis à côté de `index.html` :

- `sqlite3.wasm` : le moteur SQLite compilé en WebAssembly ;
- `drift_worker.js` : le worker qui fait tourner le moteur hors du fil
  principal.

Les deux viennent du paquet `drift` installé dans le cache pub. Ce script les
copie dans `web/`, où la construction Flutter les publie tels quels.

    python apps/limpid_app/tool/setup_web_assets.py

Les fichiers sont versionnés : sans eux, la construction web produit une
application qui n'ouvre pas sa base locale.
"""

from __future__ import annotations

import shutil
import sys
from pathlib import Path

sys.stdout.reconfigure(encoding="utf-8", errors="replace")

APP_DIR = Path(__file__).resolve().parent.parent
WEB_DIR = APP_DIR / "web"

# Les fichiers, et leur emplacement dans le paquet `drift`.
ASSETS = (
    ("drift_worker.js", "drift_worker.js"),
    (
        "sqlite3.wasm",
        "extension/devtools/build/sqlite3.wasm",
    ),
)


def find_drift_package() -> Path:
    """Trouve le paquet `drift` dans le cache pub."""
    candidates = [
        Path.home() / ".pub-cache" / "hosted" / "pub.dev",
        Path("D:/dev-caches/pub-cache/hosted/pub.dev"),
    ]
    for root in candidates:
        if not root.is_dir():
            continue
        for entry in sorted(root.glob("drift-*"), reverse=True):
            if entry.is_dir():
                return entry
    raise SystemExit(
        "Le paquet `drift` est introuvable dans le cache pub : "
        "lance `flutter pub get` avant ce script."
    )


def main() -> None:
    drift = find_drift_package()
    WEB_DIR.mkdir(parents=True, exist_ok=True)

    for name, relative in ASSETS:
        source = drift / relative
        if not source.is_file():
            raise SystemExit(f"Le fichier attendu est introuvable : {source}")
        target = WEB_DIR / name
        shutil.copyfile(source, target)
        print(f"→ {target.relative_to(APP_DIR.parent.parent)}")


if __name__ == "__main__":
    main()
