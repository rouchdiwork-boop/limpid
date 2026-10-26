# Limpid — Guide du développeur

Ce document est le point d'entrée pour reprendre le projet. Le guide complet
est dans [`docs/DEVELOPMENT.md`](docs/DEVELOPMENT.md) ; ce document donne
juste de quoi démarrer.

---

## Démarrage en cinq minutes

```bash
# 1. Vérifier la toolchain (Flutter 3.44.4, Dart 3.12.2)
flutter --version
dart --version

# 2. Installer les dépendances de tous les paquets
bash tool/bootstrap.sh          # Git Bash / Linux / macOS
powershell -File tool/bootstrap.ps1   # Windows PowerShell

# 3. Vérifier que tout est vert
bash tool/check.sh
```

`tool/check.sh` formate, analyse et teste chaque paquet du dépôt. Les paquets
qui n'existent pas encore sont ignorés : la commande reste utilisable pendant
la construction du monorepo.

## Lancer quelque chose

```bash
bash tool/run_app.sh chrome     # l'application Flutter (PWA web)
bash tool/run_app.sh windows    # l'application Flutter (desktop)
bash tool/run_api.sh            # l'API Dart Shelf
```

## Avec melos

```bash
dart pub get                    # à la racine : installe melos
dart run melos bootstrap
dart run melos run ci           # format + analyse + tests
```

melos est déclaré comme dépendance de développement de la racine : aucune
installation globale n'est nécessaire. Il reste facultatif : les scripts de
`tool/` font le même travail.

## Où aller ensuite

| Question | Document |
|---|---|
| Commandes, outillage, décisions du workspace | [`docs/DEVELOPMENT.md`](docs/DEVELOPMENT.md) |
| Produit, périmètre fonctionnel | [`docs/PROMPT.md`](docs/PROMPT.md) |
| Décisions d'architecture | [`docs/DECISIONS.md`](docs/DECISIONS.md) |
| Architecture technique | [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) |
| Feuille de route en lots | [`docs/ROADMAP.md`](docs/ROADMAP.md) |
| Fonctions v1 et leur couverture | [`docs/FEATURE_MATRIX.md`](docs/FEATURE_MATRIX.md) |
| Règles de design system | [`docs/DESIGN_SYSTEM.md`](docs/DESIGN_SYSTEM.md) |
| Participer au projet | [`CONTRIBUTING.md`](CONTRIBUTING.md) |
| Signaler une faille | [`SECURITY.md`](SECURITY.md) |

## Structure du dépôt

```
Limpid/
├─ apps/
│  ├─ limpid_app/           # Flutter : web (PWA) + mobile + desktop
│  └─ limpid_api/           # Dart Shelf sur Railway
├─ packages/
│  ├─ limpid_core/          # Dart pur : entités, CRDT, règles métier
│  ├─ limpid_design_system/ # Dart : tokens et widgets
│  ├─ limpid_quill/         # Fork de l'éditeur
│  ├─ limpid_ai/            # Passerelle IA multi-fournisseurs
│  ├─ limpid_export/        # Générateurs EPUB, PDF, DOCX
│  └─ limpid_sync/          # Client de synchronisation et transport
├─ docs/                    # Documentation normative
├─ mockups/                 # Maquettes HTML et captures de référence
├─ tool/                    # Scripts d'outillage (bash et PowerShell)
├─ tools/                   # Vérification du monorepo
├─ pubspec.yaml             # Racine du workspace Dart
└─ melos.yaml               # Configuration de l'outillage monorepo
```

## Règles à ne pas oublier

- **Immuabilité** : jamais de mutation d'un objet existant, toujours une
  nouvelle instance.
- **Aucune chaîne en dur** dans l'interface : tout passe par `l10n/`.
- **Aucun secret** dans le dépôt : variables d'environnement uniquement.
- **`limpid_core` n'importe jamais `package:flutter/*`** : c'est le contrat
  qui permet au client et au serveur de partager le modèle.
- **Une fonctionnalité est livrée avec ses tests.**
- **Un seul compilateur Dart à la fois** sur le poste : un `flutter test`
  occupe environ 450 Mo, et la machine n'a que 7,3 Go de RAM. Quand plusieurs
  agents travaillent, un seul compile, les autres attendent le verrou.
