"""Vérifie la règle de dépendance de PROMPT §5 (D-42).

La règle est un **invariant** du dépôt, pas une intention : le client et le
serveur partagent le modèle par le seul `limpid_core`, et `limpid_core` ne
doit **jamais** importer `package:flutter/*` — c'est ce qui permet aux deux
de parler du même modèle sans derive.

Le script lit les `import` et les `export` de chaque paquet — les
commentaires sont ignores, ils *parlent* de `package:flutter/*` pour
expliquer pourquoi le paquet ne l'importe pas — et sort en code 1 dès qu'un
paquet en sort.

    python tools/dependances.py            # tous les paquets
    python tools/dependances.py apps/limpid_app
"""

import pathlib
import re
import sys

RACINE = pathlib.Path(__file__).resolve().parent.parent

# Les imports et les exports d'un fichier Dart.
DIRECTIVE = re.compile(
    r"^\s*(?:import|export)\s+['\"]([^'\"]+)['\"]",
    re.MULTILINE,
)

# Les paquets du monorepo, et ce que chacun a le droit d'importer.
#
# La table vient de PROMPT §5, avec les deux corrections decidees en D-42 :
# l'editeur (`limpid_quill`) est **fait** des widgets du design system, et
# l'API importe le lecteur d'import pour la route d'import.
AUTORISES = {
    "limpid_core": frozenset(),
    "limpid_design_system": frozenset({"limpid_core"}),
    "limpid_ai": frozenset({"limpid_core"}),
    "limpid_export": frozenset({"limpid_core"}),
    "limpid_sync": frozenset({"limpid_core"}),
    "limpid_import": frozenset({"limpid_core"}),
    "limpid_quill": frozenset({"limpid_core", "limpid_design_system"}),
    "limpid_app": frozenset(
        {
            "limpid_core",
            "limpid_design_system",
            "limpid_quill",
            "limpid_ai",
            "limpid_export",
            "limpid_sync",
            "limpid_import",
        }
    ),
    "limpid_api": frozenset(
        {"limpid_core", "limpid_ai", "limpid_export", "limpid_import"}
    ),
}


def paquets() -> list[pathlib.Path]:
    """Les dossiers du monorepo qui portent un `pubspec.yaml`."""
    trouves = []
    for motif in ("packages/*", "apps/*"):
        for chemin in sorted(RACINE.glob(motif)):
            if (chemin / "pubspec.yaml").exists():
                trouves.append(chemin)
    return trouves


def nom_du_paquet(dossier: pathlib.Path) -> str:
    """Le nom du paquet, tel que `pubspec.yaml` le declare."""
    for ligne in (dossier / "pubspec.yaml").read_text(encoding="utf-8").splitlines():
        if ligne.startswith("name:"):
            return ligne.split(":", 1)[1].strip()
    return dossier.name


def est_dart_pur(dossier: pathlib.Path) -> bool:
    """Le paquet est-il du Dart pur, sans Flutter ?

    Un paquet qui ne depend pas du SDK Flutter ne peut pas importer
    `package:flutter/*` : le paquet ne pourrait pas etre compile par le
    serveur, qui n'a pas Flutter.
    """
    contenu = (dossier / "pubspec.yaml").read_text(encoding="utf-8")
    return "sdk: flutter" not in contenu


def imports_reels(dossier: pathlib.Path) -> list[tuple[pathlib.Path, str]]:
    """Les paquets importes par le dossier, avec le fichier qui les importe.

    Les commentaires sont ignores : un paquet peut *parler* de
    `package:flutter/*` pour expliquer qu'il ne l'importe pas.
    """
    trouves = []
    for fichier in sorted((dossier / "lib").rglob("*.dart")):
        lignes = [
            ligne
            for ligne in fichier.read_text(encoding="utf-8").splitlines()
            if not ligne.lstrip().startswith("//")
        ]
        for adresse in DIRECTIVE.findall("\n".join(lignes)):
            trouves.append((fichier, adresse))
    return trouves


def verifier(dossier: pathlib.Path) -> list[str]:
    """Les fautes de dependance du paquet, une par ligne."""
    nom = nom_du_paquet(dossier)
    if nom not in AUTORISES:
        return [
            f"{dossier.relative_to(RACINE)} : le paquet '{nom}' n'est pas "
            "décrit par la règle de dépendance."
        ]

    autorises = AUTORISES[nom]
    pur = est_dart_pur(dossier)
    fautes = []

    for fichier, adresse in imports_reels(dossier):
        if adresse.startswith("dart:"):
            continue
        if not adresse.startswith("package:"):
            continue
        cible = adresse[len("package:") :].split("/")[0]
        if cible == "flutter":
            if pur:
                fautes.append(
                    f"{fichier.relative_to(RACINE)} : '{nom}' est du Dart pur, "
                    "il ne doit pas importer 'package:flutter/*'."
                )
            continue
        if cible == nom:
            # Un paquet s'exporte lui-meme : son baril est son point
            # d'entree.
            continue
        if cible.startswith("limpid_") and cible not in autorises:
            fautes.append(
                f"{fichier.relative_to(RACINE)} : '{nom}' n'a pas le droit "
                f"d'importer '{cible}'."
            )

    return fautes


def main() -> int:
    cibles = sys.argv[1:]
    dossiers = paquets()
    if cibles:
        dossiers = [
            dossier
            for dossier in dossiers
            if any(cible in str(dossier) for cible in cibles)
        ]

    fautes = []
    for dossier in dossiers:
        fautes.extend(verifier(dossier))

    if fautes:
        print("La règle de dépendance de PROMPT §5 est violée :\n")
        for faute in fautes:
            print(f"  {faute}")
        print(f"\n{len(fautes)} faute(s).")
        return 1

    print(f"OK : {len(dossiers)} paquets respectent la règle de dépendance.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
