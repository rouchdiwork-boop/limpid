# limpid_export

Moteur d'export de livres de **Limpid**. Generateurs **natifs Dart**, hors
ligne, sans service externe : EPUB 3, PDF (reflowable et print-ready), DOCX,
HTML, Markdown et ODT.

Le package ne depend **pas** de `limpid_core` : il expose son propre modele
d'entree intermediaire (`ExportBook`) que l'application traduit depuis son
modele interne. Aucune dependance Flutter : le package fonctionne sur
desktop, mobile et web.

## Usage

```dart
import 'package:limpid_export/limpid_export.dart';

final exporter = LimpidExporter();
final result = await exporter.export(
  ExportFormat.epub3,
  book,
  const ExportOptions(),
);

print('${result.fileName} (${result.bytes.length} octets)');
for (final warning in result.warnings) {
  print('Attention : $warning');
}
```

Les ecritures directes restent possibles, writer par writer :

```dart
final bytes = await const Epub3Writer().write(book, const ExportOptions());
```

Chaque writer expose la meme API (`Future<Uint8List> write(ExportBook,
ExportOptions)`) et n'utilise aucun widget : il est testable sans Flutter.

## Formats

| Format | Contenu |
|---|---|
| `ExportFormat.epub3` | EPUB 3 valide : `mimetype` stocke en premier, `META-INF/container.xml`, `OEBPS/content.opf` (manifeste, spine, Dublin Core, ISBN, BISAC, `dcterms:modified`), `OEBPS/nav.xhtml`, `OEBPS/toc.ncx`, un XHTML par chapitre, CSS embarque |
| `ExportFormat.pdfReflowable` | PDF pagine automatiquement : page de couverture, page de titre, sommaire, titre courant, numeros de page, signets cliquables |
| `ExportFormat.pdfPrintReady` | PDF d'impression : format final (trim), marges interieures/exterieures en miroir, fond perdu, images a 300 dpi, code-barres EAN-13 sur la page de garde |
| `ExportFormat.docx` | WordprocessingML : styles Titre 1/2/3 et Corps, saut de section par chapitre, images, notes de bas de page, proprietes |
| `ExportFormat.html` | HTML semantique autonome (CSS inline) pour ebook |
| `ExportFormat.htmlLanding` | Page de vente : balises Open Graph et JSON-LD `Book` |
| `ExportFormat.markdown` | Markdown avec front matter YAML, notes de bas de page |
| `ExportFormat.odt` | Paquet OpenDocument Text : `mimetype` stocke, `manifest.xml`, `content.xml`, `styles.xml`, `meta.xml` |

## Modele d'entree

```
ExportBook  { title, subtitle, authors[], language, metadata, coverImage, chapters[] }
ExportChapter { title, order, identifier, blocks[] }
ExportBlock  { type, text, href?, level?, footnotes[], image? }
ExportMetadata { isbn, description, publisher, rights, publicationDate, bisac[], subjects[] }
```

Le type de bloc (`paragraph`, `heading1..3`, `listItem`, `quote`, `code`,
`image`, `pageBreak`, `footnote`) suffit a piloter la typographie de chaque
format cible.

## Couverture dans le PDF

Le PDF **embarque la couverture** du livre (`ExportOptions.includeCoverImage`,
`ExportBook.coverImage`) :

- une couverture **SVG** — celle du generateur de couverture — est rendue
  en **vecteurs** par le moteur PDF : le degrade et les textes restent du
  vectoriel dans le fichier produit, sans rasterisation ;
- une couverture **matricielle** (PNG, JPEG) est embarquee comme image.

La couverture occupe la page entiere en lecture, et le format final en
impression : le fond perdu reste hors de la couverture. Une couverture
illisible est signalee dans `ExportResult.warnings` et abandonnee ; l'export
produit alors un PDF valide, sans page vide.

## Code-barres EAN-13

L'edition imprimee (`ExportFormat.pdfPrintReady`) porte un code-barres
EAN-13 sur sa page de garde, construit a partir de
`ExportMetadata.isbn` :

- l'ISBN est lu avec ou sans tiret ni espace, et sa cle de controle est
  verifiee ;
- l'ISBN-13 de l'edition imprimee est celui de la plage `979` : le prefixe
  `978` d'un ISBN-13 deja acquis y est transcrit, prefixe remplace et cle
  recalculee ; un ISBN-10 valide est converti de la meme facon ;
- le symbole compte 95 modules (gardes, six chiffres de part et d'autre du
  garde central) et 18 modules de zones de silence.

Le code n'apparait que si l'ISBN est present et valide. Son absence n'est
pas une erreur : l'export la signale dans `ExportResult.warnings`, plutot
que de produire un fichier muet.

## Polices

Les polices sont **embarquees en assets** (OFL), jamais telechargees. Voir
`assets/fonts/README.md`. En l'absence des fichiers, le moteur PDF utilise ses
polices de substitution et signale l'evenement dans `ExportResult.warnings`.

## Tests

```bash
dart pub get
dart analyze
dart test
```

## Ecarts par rapport a D-09

- **`printing` n'est pas utilise** : ce package est un plugin Flutter
  (`flutter: sdk: flutter`) destine a l'UI (`Printing.sharePdf`, `PdfPreview`).
  Il ne peut pas etre dependance par un package Dart pur, et le partage
  clavier/aperçu n'a pas sa place dans un moteur d'export. L'application
  Flutter utilisera `printing` pour l'aperçu et le partage.
- **Le DOCX est genere par le package** : le paquet `docx` n'existe plus sur
  pub.dev (404 sur pub.dev et sur ses miroirs). Le format OOXML etant un ZIP
  de documents XML, il est produit par les generateurs de ce package
  (`lib/src/docx/`), sur le meme modele que l'EPUB et l'ODT.
- **Le HTML et le Markdown n'ont aucune dependance** : ecriture directe, sans
  bibliotheque de templates.
