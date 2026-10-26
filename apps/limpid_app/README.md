# limpid_app

L'application Limpid : **web, mobile et desktop** à partir d'une seule base
Flutter 3.44 / Dart 3.12.

## Lancer

```bash
flutter pub get
dart run build_runner build --delete-conflicting-outputs   # providers Riverpod
flutter gen-l10n                                            # localisations fr / en
flutter run -d chrome                                       # web
flutter run -d windows                                      # desktop
```

## Mode démonstration

Sans configuration, l'application démarre **en mode démonstration** : la session
s'ouvre localement, sans réseau. L'écran de connexion affiche un bandeau qui
l'explique. C'est ce mode qui permet de parcourir toute l'interface sur une
machine neuve.

## Brancher un backend Supabase

```bash
flutter run -d chrome \
  --dart-define=SUPABASE_URL=https://<projet>.supabase.co \
  --dart-define=SUPABASE_PUBLISHABLE_KEY=<clé publiable>
```

La clé publiable est publique par conception ; **jamais** la clé secrète.
L'authentification passe par un lien magique : l'auteur ne crée pas de mot de
passe.

## Structure

```
lib/
├── main.dart                    Point d'entrée : bootstrap, composition
├── l10n/                        Messages fr / en (ARB) + code généré
└── src/
    ├── app/                     Coquille : router, thèmes, composition
    ├── auth/                    Dépôt d'authentification, session
    ├── bootstrap/               Initialisation (Supabase, mode démo)
    ├── data/                    Base SQLite, client API, synchronisation
    ├── domain/                  Contrats et ports de persistance
    ├── editor/                  Contrôleur de l'écran d'écriture
    ├── features/                Un dossier par fonctionnalité
    │   ├── auth/                Connexion, inscription
    │   ├── dashboard/           Bureau
    │   ├── library/             Bibliothèque
    │   ├── onboarding/          Assistant de démarrage
    │   ├── project/             Fiche projet, sélecteur de livre
    │   ├── projects/            Données des projets, couverture
    │   ├── settings/            Réglages
    │   └── writing/             Surface d'écriture
    └── shell/                   Coquille adaptative (rail / barre basse)
web/                             Coquille PWA : manifeste, favicon, icônes
tool/generate_icons.py           Génère les icônes PWA depuis tokens.json
tool/setup_web_assets.py         Copie les fichiers WASM de Drift pour le web
```

## Identité de la PWA

Le manifeste, le favicon et les icônes d'installation portent la marque
Limpid. Les couleurs ne sont pas écrites en dur : elles sont lues dans
`packages/limpid_design_system/tokens.json`, la source de vérité.

```bash
python tool/generate_icons.py
```

Le marque est le « L. » des maquettes : un L en `fgDefault` et un point en
`accent`, le seul accent de la marque.

## Base locale sur le web

Drift ouvre une base SQLite dans un navigateur par deux fichiers servis à
côté de `index.html` : `sqlite3.wasm` (le moteur compilé en WebAssembly) et
`drift_worker.js` (le worker qui le fait tourner). Ils viennent du paquet
`drift` du cache pub.

```bash
python tool/setup_web_assets.py
```

Les deux fichiers sont versionnés : sans eux, la construction web produit une
application qui n'ouvre pas sa base locale.

## Règles appliquées

- **Aucune couleur, police, taille ni padding littéral** : tout passe par
  `context.limpid` et les widgets `Limpid*` du design system.
- **Aucune chaîne en dur** : les textes viennent de `AppLocalizations`.
- Les écrans s'adaptent : rail de navigation au-delà de 900 px, barre basse en
  dessous.
- Accessibilité : cibles de 44 px, focus visible, `Semantics` sur chaque
  contrôle interactif.
- **Les écrans ne connaissent que les contrats** de `lib/src/domain/` : la
  base locale et l'API sont choisies au point de composition
  (`lib/src/app/dependencies.dart`), jamais par l'écran lui-même (D-31).

## Couches

| Couche | Dossier | Contenu |
|---|---|---|
| Contrat | `lib/src/domain/` | Les interfaces de persistance, les ports Riverpod |
| Implémentation | `lib/src/data/` | La base SQLite (Drift), le client HTTP, la synchronisation |
| Écrans | `lib/src/features/` | Un dossier par fonctionnalité |

## Vérification

```bash
flutter analyze   # 0 erreur, 0 avertissement
flutter test      # 126 tests
dart format --set-exit-if-changed .
```

## En cours

L'application est branchée sur ses données réelles : l'éditeur de manuscrit
vient de `packages/limpid_quill`, la synchronisation de `packages/limpid_sync`,
la persistance locale de `lib/src/data/`. Les lots 3 (révision et
collaboration) et 6 (vitrine, Stripe, KDP) restent à faire.
