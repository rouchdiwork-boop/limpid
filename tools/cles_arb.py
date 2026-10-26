"""Vérifie que les fichiers ARB d'un paquet portent les mêmes clés.

Une clé présente dans une seule langue n'est pas une faute de frappe : elle
disparaît silencieusement à l'exécution, et l'interface affiche le message
du gabarit — en français pour un lecteur anglophone.

Le script compare les ensembles de clés de tous les fichiers `*.arb` d'un
même répertoire et sort en code 1 dès qu'un écart existe.

    python tools/cles_arb.py            # tous les paquets
    python tools/cles_arb.py apps/limpid_app
"""

import json
import pathlib
import sys

RACINE = pathlib.Path(__file__).resolve().parent.parent


def repertoires() -> list[pathlib.Path]:
    """The directories that hold the localizations of the monorepo."""
    trouves = []
    for motif in ("packages/*", "apps/*"):
        for chemin in sorted(RACINE.glob(motif)):
            if (chemin / "l10n.yaml").exists():
                trouves.append(chemin)
    return trouves


def cles(fichier: pathlib.Path) -> set[str]:
    """The keys of an ARB file, metadata excluded."""
    donnees = json.loads(fichier.read_text(encoding="utf-8"))
    return {
        cle
        for cle in donnees
        if not cle.startswith("@")
    }


def verifier(dossier: pathlib.Path) -> int:
    """Compares the ARB files of a package. Returns the number of faults."""
    fichiers = sorted((dossier / "lib" / "l10n").glob("*.arb"))
    if len(fichiers) < 2:
        return 0

    reference = fichiers[0]
    cles_reference = cles(reference)
    fautes = 0

    for fichier in fichiers[1:]:
        cles_fichier = cles(fichier)
        manquantes = sorted(cles_reference - cles_fichier)
        en_trop = sorted(cles_fichier - cles_reference)

        if not manquantes and not en_trop:
            continue

        fautes += 1
        print(f"ECHEC {fichier.relative_to(RACINE)}")
        for cle in manquantes:
            print(f"    clé absente : {cle}")
        for cle in en_trop:
            print(f"    clé en trop  : {cle}")

    if fautes == 0:
        print(f"OK {dossier.relative_to(RACINE)} : {len(cles_reference)} cles communes")
    return fautes


def main() -> int:
    dossiers = [pathlib.Path(arg) for arg in sys.argv[1:]] or repertoires()
    if not dossiers:
        print("Aucun paquet porte de localisation.")
        return 0

    fautes = 0
    for dossier in dossiers:
        fautes += verifier(dossier)

    if fautes:
        print(f"\n{fautes} paire(s) de fichiers ARB désaccordées.")
        return 1

    print("\nTous les fichiers ARB portent les mêmes clés.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
