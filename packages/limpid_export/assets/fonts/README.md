# Polices embarquees

Ce dossier accueille les faces de police **OFL** utilisees par le moteur
d'export PDF (cf. D-13 de `docs/DECISIONS.md`). Elles sont livrees en assets
par l'application Flutter : elles ne sont **jamais** telechargees a
l'execution (le mode hors-ligne est une exigence non negociable).

## Fichiers attendus

Le registre (`lib/src/fonts/embedded_font.dart`) attend exactement ces noms :

| Famille | Fichiers | Usage |
|---|---|---|
| `Literata` | `Literata-Regular.ttf`, `Literata-Bold.ttf`, `Literata-Italic.ttf`, `Literata-BoldItalic.ttf` | manuscrit et corps de texte |
| `Fraunces` | `Fraunces-Regular.ttf`, `Fraunces-Bold.ttf`, `Fraunces-Italic.ttf`, `Fraunces-BoldItalic.ttf` | titres et page de titre |
| `Instrument Sans` | `InstrumentSans-Regular.ttf`, `InstrumentSans-Bold.ttf`, `InstrumentSans-Italic.ttf`, `InstrumentSans-BoldItalic.ttf` | interface |
| `IBM Plex Mono` | `IBMPlexMono-Regular.ttf`, `IBMPlexMono-Bold.ttf`, `IBMPlexMono-Italic.ttf`, `IBMPlexMono-BoldItalic.ttf` | code et metadonnees |

Les licences OFL correspondantes doivent etre livrees a cote des fichiers
(`OFL-Literata.txt`, `OFL-Fraunces.txt`, ...).

## Injection dans le moteur

Le package est en Dart pur : il n'a aucun acces aux assets. C'est
l'application qui fournit un chargeur :

```dart
final exporter = LimpidExporter(
  fontRegistry: FontRegistry(
    loader: (path) async => rootBundle.load(path),
  ),
);
```

## Comportement par defaut

Les fichiers de police **ne sont pas versionnes dans ce depot**. Tant qu'ils
ne sont pas fournis :

- le moteur PDF utilise ses polices de substitution livrees avec la
  bibliotheque `pdf` (Times, Helvetica, Courier) ;
- un avertissement non bloquant est emis dans `ExportResult.warnings` ;
- les caracteres hors Latin-1 (apostrophe typographique, tiret cadratin...)
  sont translitteres, faute de glyphe disponible.

**TODO** : deposer les faces OFL dans ce dossier (ou dans les assets de
`apps/limpid_app`) et supprimer la note de substitution du rapport de
livraison. Le build n'est pas bloque par leur absence.
