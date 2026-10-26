# limpid_import

Moteur d'import de manuscrits de Limpid : six formats lus, une seule
structure rendue.

Les formats lus sont **DOCX**, **ODT**, **EPUB**, **RTF**, **Markdown** et
**TXT**. Tous rendent la même chose : une hiérarchie de chapitres, de scènes
et de blocs. Un import ne fait jamais un seul bloc, et il n'invente pas ce
que le fichier ne porte pas.

## Le point d'entrée

```dart
import 'package:limpid_import/limpid_import.dart';

final ImportedManuscript manuscript = await const LimpidImporter().import(
  ImportRequest(fileName: 'livre.docx', bytes: bytes),
);

print(manuscript.chapterCount);   // 3
print(manuscript.sceneCount);     // 12
print(manuscript.blockCount);     // 87
print(manuscript.skipped);        // ce que l'import a laissé de côté
```

## La structure rendue

```
ImportedManuscript
  title
  chapters : List<ImportedChapter>
    title
    level        (le niveau du titre : 1, 2, 3)
    scenes : List<ImportedScene>
      title
      blocks : List<ImportedBlock>   (paragraphes, listes, citations, code)
```

- une **liste** Markdown devient **plusieurs** blocs : chaque élément est un
  bloc à part entière ;
- un bloc `code` garde son **langage** quand le fichier source le déclare ;
- un **chapitre** porte le niveau de son titre : le niveau porte la
  hiérarchie, la liste porte l'ordre.

## Comment chaque format est lu

| Format | Ce qui est lu | Ce qui ouvre un chapitre | Ce qui coupe une scène |
|---|---|---|---|
| Markdown | les titres `#`, `##`, `###` et le corps | un titre | un séparateur horizontal (`***`, `---`) |
| TXT | le texte | le fichier entier | une ligne vide |
| DOCX | `word/document.xml`, les styles `w:pStyle` | un style de titre (`Heading1`, `Titre1`…) | un saut de page |
| ODT | `content.xml`, les `text:h` et leur niveau | un `text:h` | un saut de page souple |
| EPUB | `META-INF/container.xml`, l'OPF, la spine, les documents XHTML | un document de la spine | un titre interne au document |
| RTF | le texte, `\outlinelevelN`, `\sect`, `\par` | un niveau de plan ou une section | un saut de page (`\page`) |

Les règles qui ne varient pas d'un format à l'autre :

- un chapitre sans titre reçoit le nom « Chapitre N » ;
- le manuscrit porte le titre interne du fichier quand il en a un, sinon
  le nom du fichier sans son extension ;
- une scène sans bloc et un chapitre sans scène ne sont jamais rendus.

## Ce que l'import annonce

L'import ne cache pas ses limites : `ImportedManuscript.skipped` porte ce
qui n'a pas été importé.

| Raison | Ce qui est laissé de côté |
|---|---|
| `images` | les images du fichier source |
| `notes` | les notes de bas de page et les appels de note |
| `comments` | les commentaires et les annotations |

## Les dépendances

Le paquet ne dépend que du SDK et des deux bibliothèques déjà présentes dans
l'arbre du monorepo :

- `archive` pour les paquets ZIP (DOCX, ODT, EPUB) ;
- `xml` pour les documents XML (OOXML, ODF, XHTML, OPF).

## Les fichiers d'essai

La bibliothèque `package:limpid_import/testing.dart` construit de **vrais**
fichiers : un DOCX, un ODT et un EPUB sont des paquets ZIP que Word,
LibreOffice et les lecteurs EPUB ouvrent. Une fixture qui ne s'ouvre pas ne
prouve rien.

```dart
import 'package:limpid_import/testing.dart';

final bytes = buildDocx();   // un DOCX valide
```
