# Limpid — Design System

> Document **normatif**. Le code fait foi : `packages/limpid_design_system/`.
> Ce document explique l'intention, les règles et les interdits ; les valeurs
> exactes vivent dans `tokens/colors.dart`, `tokens/typography.dart`, etc., et
> sont exportées en `tokens.json` pour Figma et les maquettes.

**Version** : 1.0 — gelée le 2026-10-25
**Direction artistique** : *Éditorial Contemporain*
**Public** : auteurs indépendants, en français d'abord

---

## 1. Principe directeur

Limpid est un **atelier**, pas un tableau de bord. L'écran d'écriture doit
ressembler à une page de papier tenue dans un logiciel rapide, et l'interface
autour doit disparaître.

Trois conséquences de design en découlent :

1. **Le manuscrit est un composant de premier plan**, pas un champ de formulaire.
   Il a sa propre typographie (`Literata`), sa propre largeur de ligne (65 signes),
   son propre thème (Papier / Sépia), et il peut occuper tout l'écran.
2. **L'interface est en retrait.** Sur fond papier, l'interface utilise des
   surfaces légèrement plus sombres ou plus claires que le manuscrit, jamais
   l'inverse, pour que le texte écrit reste l'élément le plus contrasté de l'écran.
3. **L'IA est un enableur, pas un ornement.** Les surfaces IA (panneau latéral,
   suggestions inline) utilisent la teinte *aether* (indigo), jamais le brass
   de la marque. On distingue ainsi « ce que vous écrivez » de « ce que la
   machine propose ».

---

## 2. Couleurs

### 2.1 Les quatre thèmes

| Thème | Rôle | Fond |
|---|---|---|
| **Papier** (`paper`) | Défaut, travail quotidien | `#FAF8F4` |
| **Sépia** (`sepia`) | Lecture longue, impression, mode « page » | `#F4EBD8` |
| **Nuit** (`night`) | Écriture nocturne | `#14110E` |
| **Contraste élevé** (`contrast`) | Accessibilité — exigence, pas option premium | `#000000` |

Le thème est un choix global unique, synchronisé entre tous les appareils.
Le thème `sepia` est proposé **par défaut dans l'éditeur de manuscrit** quand
l'appareil est en mode sombre : c'est le seul écran où le changement de thème
est contextuel.

### 2.2 Table canonique

Cette table est la source de vérité partagée avec le package Dart, `tokens.json`
et les maquettes HTML. **Toute modification se fait ici d'abord.**

L'alignement des trois sources est vérifié par le test
`packages/limpid_design_system/test/sources_parity_test.dart` : une couleur qui
diverge entre ce document, `tokens.json` et les maquettes fait échouer la
suite. On ne peut donc pas modifier un côté sans modifier les autres.

#### Surfaces et texte

| Token | Papier | Sépia | Nuit | Contraste |
|---|---|---|---|---|
| `bgCanvas` | `#FAF8F4` | `#F4EBD8` | `#14110E` | `#000000` |
| `bgSurface` | `#FFFFFF` | `#FBF6EA` | `#1C1915` | `#000000` |
| `bgRaised` | `#FFFFFF` | `#FFFDF8` | `#242019` | `#0A0A0A` |
| `bgSunken` | `#F2EEE6` | `#E9DEC6` | `#0F0D0A` | `#000000` |
| `fgDefault` | `#16130F` | `#33281A` | `#F0EBE2` | `#FFFFFF` |
| `fgMuted` | `#57504A` | `#6B5C48` | `#A79E92` | `#FFFFFF` |
| `fgSubtle` | `#857C72` | `#8C7C64` | `#7A7268` | `#E6E6E6` |
| `borderSubtle` | `#E7E1D6` | `#DFD3B8` | `#2B261F` | `#FFFFFF` |
| `borderDefault` | `#D8D0C2` | `#CDBFA0` | `#3A332A` | `#FFFFFF` |
| `borderStrong` | `#BCB2A0` | `#B3A184` | `#4C4438` | `#FFFFFF` |

#### Accent de marque — *brass* (laiton / cuivre)

| Token | Papier | Sépia | Nuit | Contraste |
|---|---|---|---|---|
| `accent` | `#9C5518` | `#8E4A12` | `#E0A460` | `#FFB454` |
| `accentHover` | `#83450F` | `#763C0B` | `#F0BC85` | `#FFC87A` |
| `accentPressed` | `#6E3909` | `#633207` | `#C98E4A` | `#D99338` |
| `accentSubtle` | `#F6E7D6` | `#F0E0C8` | `#2E2418` | `#2A2013` |
| `accentBorder` | `#E4C4A0` | `#DCBC93` | `#4A3A22` | `#6B5223` |
| `fgOnAccent` | `#FFFFFF` | `#FFFFFF` | `#1A1207` | `#000000` |

> **Usage.** Le brass est le **seul** accent de la marque. Il signale l'action
> principale (Enregistrer, Publier, Générer), la progression, et l'état actif
> de la navigation. Il ne sert jamais à_encoder un statut.

#### Secondaire — *aether* (IA, collaboration, présence)

| Token | Papier | Sépia | Nuit | Contraste |
|---|---|---|---|---|
| `secondary` | `#35407E` | `#2F3A72` | `#9BA4E8` | `#AEB6F5` |
| `secondarySubtle` | `#E8EAF7` | `#E4E7F5` | `#1E2138` | `#1A1D2E` |

> **Usage.** Réservé aux surfaces IA, aux curseurs distants et aux indicateurs
> de présence. Un utilisateur doit pouvoir dire « ceci est de la machine »
> sans lire le libellé.

#### Statuts — sémantique, **distincte** de l'accent

| Token | Papier | Sépia | Nuit | Contraste |
|---|---|---|---|---|
| `success` | `#3E6B4F` | `#356043` | `#7FB093` | `#6ED79B` |
| `warning` | `#8A6410` | `#7A5810` | `#D9A845` | `#FFC44D` |
| `danger` | `#A8341F` | `#97301C` | `#E08573` | `#FF8A72` |
| `info` | `#2E5F7A` | `#28566F` | `#7FB3CE` | `#7FD4F5` |

> **Règle d'or.** Aucun statut n'est porté par la couleur seule. Un statut =
> **couleur + icône + texte**. Exemple : `danger` toujours accompagné d'une
> icône d'alerte et du libellé « Échec de l'export ».

### 2.3 Contrastes vérifiés

| Paire | Papier | Sépia | Nuit | Contraste |
|---|---|---|---|---|
| `fgDefault` / `bgCanvas` | 15,8:1 ✅ | 12,4:1 ✅ | 14,1:1 ✅ | 21:1 ✅ |
| `fgMuted` / `bgCanvas` | 7,4:1 ✅ | 5,8:1 ✅ | 6,9:1 ✅ | 21:1 ✅ |
| `fgSubtle` / `bgCanvas` | 3,9:1 ⚠ | 3,7:1 ⚠ | 3,6:1 ⚠ | 15:1 ✅ |
| `fgOnAccent` / `accent` | 5,6:1 ✅ | 6,3:1 ✅ | 9,4:1 ✅ | 11,2:1 ✅ |
| `accent` / `bgCanvas` | 5,5:1 ✅ | 5,7:1 ✅ | 8,1:1 ✅ | 10,2:1 ✅ |

`fgSubtle` est réservé aux textes **non essentiels** (horodatages, compteurs
secondaires, placeholders). Tout texte porteur d'information doit utiliser
`fgDefault` ou `fgMuted`.

---

## 3. Typographie

### 3.1 Les quatre familles

| Rôle | Face | Pourquoi |
|---|---|---|
| **Display / titres** | **Fraunces** | Serif variable à l'identité éditoriale forte (axes `SOFT`, `WONK`). Apporte la chaleur d'un livre imprimé sans être un Didone générique. |
| **Interface** | **Instrument Sans** | Grotesque contemporaine, un peu idiosyncratic, très lisible à 13–16 px. |
| **Manuscrit** | **Literata** | Dessinée pour la lecture longue ; OpenType soigné (ligatures discrètes, chiffres elzéviriens). |
| **Données** | **IBM Plex Mono** | Métadonnées, ISBN, compteurs de mots, journaux. Donne un registre « métier » sans casser l'harmonie. |

Toutes sont **SIL Open Font License** et donc embarquables.

> **Interdiction absolue.** `google_fonts` est interdit en production : il
> télécharge les polices au runtime, ce qui casse le premier rendu et le mode
> hors-ligne. Les fichiers `.ttf` sont dans `assets/fonts/` et déclarés dans le
> `pubspec.yaml`.

### 3.2 Échelle typographique

| Style | Taille / Interligne | Graisse | Face | Usage |
|---|---|---|---|---|
| `displayXl` | 40 / 42 | 600 | Fraunces | Titre d'écran (grand) |
| `displayL` | 32 / 38 | 600 | Fraunces | Titre de page |
| `displayM` | 26 / 32 | 600 | Fraunces | Nom du livre |
| `titleL` | 22 / 28 | 600 | Fraunces | Titre de section majeur |
| `titleM` | 18 / 24 | 600 | Fraunces | Titre de carte, titre de panneau |
| `titleS` | 15 / 21 | 600 | Instrument Sans | Titre de groupe, d'onglet |
| `bodyL` | 16 / 26 | 400 | Instrument Sans | Texte principal d'interface |
| `bodyM` | 14 / 22 | 400 | Instrument Sans | Texte courant |
| `bodyS` | 13 / 20 | 400 | Instrument Sans | Texte secondaire, aide |
| `label` | 12 / 16 | 500 | Instrument Sans | Libellé, uppercase, `ls 0.06em` |
| `caption` | 11 / 15 | 500 | Instrument Sans | Légende, horodatage, `ls 0.04em` |
| `mono` | 13 / 20 | 400 | IBM Plex Mono | Données, identifiants |
| `manuscript` | 18 / 32 | 400 | Literata | Corps du manuscrit |
| `manuscriptSm` | 16 / 28 | 400 | Literata | Manuscrit compact, lectures d'écran étroit |

### 3.3 Règles de composition

- **Largeur de ligne du manuscrit** : 65 signes maximum, `max-width: 68ch`,
  centré, avec un décalageOptical : le texte commence à `x = 8ch` du bord de la
  colonne pour aligner la première lettre des lignes courtes.
- **Titres** : `text-wrap: balance` en web, `Flutter` via `softWrap` + mesure
  manuelle de la hauteur.
- **Capitales / labels** : `letter-spacing` 0.06em, jamais de texte tout en
  capitales au-delà de 3 mots. La mise en capitales du token `label` est
  réservée aux **libellés de formulaire** et aux **titres de section**, courts
  par construction. **Les libellés de bouton restent en casse de phrase** :
  « Recevoir mon lien d'accès » ne doit jamais apparaître en capitales.
- **Chiffres** : `font-variant-numeric: tabular-nums` **partout où des chiffres
  s'alignent en colonne** (statistiques, tableaux, prix, dates).
- **Interdiction** : texte justifié dans l'interface (le manuscrit, lui, autorise
  l'alignement justifié en option utilisateur).

---

## 4. Espacements

Base **4 pt**. L'échelle complète :

```
0 · 2 · 4 · 6 · 8 · 12 · 16 · 20 · 24 · 32 · 40 · 48 · 64 · 80 · 96 · 128
```

| Contexte | Valeur |
|---|---|
| Icône ↔ texte dans un bouton | 8 |
| Champ de formulaire ↔ label | 8 |
| Champ de formulaire ↔ champ suivant | 16 |
| Carte ↔ carte (grille) | 16 (mobile) / 20 (desktop) |
| Section ↔ section | 40 |
| Conteneur ↔ contenu | 16 (mobile) / 24 (tablet) / 32 (desktop) |
| Padding de panneau latéral | 20 |
| Padding de barre d'outils | 8 / 12 |

**Interdit** : toute marge non issue de l'échelle. L'espacement se fait par
`gap` / `padding`, jamais par des marges qui s'effondrent.

---

## 5. Rayons

| Token | Valeur | Usage |
|---|---|---|
| `radiusXs` | 4 | Puce, badge minuscule, tag |
| `radiusSm` | 6 | Champ de formulaire, bouton compact |
| `radiusMd` | 10 | Bouton, champ, carte moyenne |
| `radiusLg` | 14 | Carte, panneau, dialogue |
| `radiusXl` | 20 | Feuille modale, carte de couverture |
| `radiusXxl` | 28 | Carte de.feature, hero |
| `radiusPill` | 999 | Badge de statut, interrupteur, puce |

**Règle de cohérence** : un composant garde le même rayon dans tous ses états.
Un bouton `radiusMd` ne devient pas `radiusPill` au survol.

---

## 6. Élévation

| Token | Papier / Sépia | Nuit | Usage |
|---|---|---|---|
| `elevation0` | aucune | aucune | Surface plane |
| `elevation1` | `0 1px 2px rgba(22,19,15,.06), 0 1px 1px rgba(22,19,15,.04)` | `0 1px 2px rgba(0,0,0,.5)` + hairline `borderSubtle` | Barre collante, champ |
| `elevation2` | `0 2px 6px rgba(22,19,15,.08)` | `0 2px 8px rgba(0,0,0,.55)` | Menu, popup |
| `elevation3` | `0 8px 24px rgba(22,19,15,.12)` | `0 8px 28px rgba(0,0,0,.6)` | Dialogue, feuille modale |
| `elevation4` | `0 20px 48px rgba(22,19,15,.16)` | `0 20px 56px rgba(0,0,0,.65)` | Commande palette, plein écran |

En thème nuit, l'ombre seule ne suffit plus : **toute surface élevée reçoit
aussi une bordure hairline** `borderSubtle`.

---

## 7. Mouvement

| Token | Durée | Usage |
|---|---|---|
| `motionInstant` | 0 ms | Changement d'état immédiat |
| `motionFast` | 120 ms | Survol, focus, puce |
| `motionBase` | 180 ms | Ouverture de panneau, changement de thème |
| `motionSlow` | 260 ms | Transition de vue, apparition de carte |
| `motionSlower` | 400 ms | Ouverture de dialogue, coach-mark |

**Courbes** : `standard cubic-bezier(0.2, 0, 0, 1)` · `decelerate cubic-bezier(0, 0, 0, 1)` ·
`exit cubic-bezier(0.4, 0, 1, 1)` · `emphasized cubic-bezier(0.2, 0, 0, 1)`.

**Règles.**
- Rien ne bouge au-delà de 400 ms.
- Le mouvement sert à expliquer une cause → effet (le panneau s'ouvre **depuis**
  le bouton qui l'a ouvert).
- `prefers-reduced-motion` / `MediaQuery.disableAnimations` : les durées tombent
  à 0, **jamais** à une animation de repli.
- La saisie au clavier n'anime **jamais** le texte ni le curseur.
- Le défilement fluide est réservé à la navigation programmatique (allers-retours
  dans l'éditeur).

---

## 8. Iconographie

- **Source** : **Lucide** (ISC), via `lucide_icons_flutter`. Traits de 1,5 px,
  grille 24×24, coins arrondis.
- **Tailles** : 16 (inline dans un texte), 20 (bouton, champ), 24 (navigation),
  32 (illustration d'état vide).
- **Règle** : une icône d'action a toujours un libellé visible ou une infobulle
  au survol, **sauf** dans le cas d'une icône étiquetée par un groupe (barre
  d'outils).
- Les icônes ne portent jamais seules une information critique : elles
  accompagnent un libellé.

---

## 9. Mise en page

### 9.1 Points de rupture

| Nom | Largeur | Adaptation |
|---|---|---|
| `compact` | < 600 | Mobile : navigation basse, panneaux en feuille modale |
| `medium` | 600 – 1240 | Tablette : navigation en rail, panneaux en overlay |
| `expanded` | ≥ 1240 | Desktop : 3 panneaux, navigation en rail permanent |
| `large` | ≥ 1600 | Desktop large : colonne de contexte supplémentaire |

### 9.2 Coquille d'application

**Desktop (≥ 1240 px)** — 3 colonnes :

```
┌────────────┬──────────────────────────────┬───────────────┐
│  Rail 240  │  Zone de travail (flex)      │  Panneau 320  │
│  navigation│  plan / écriture / relecture │  IA / biblio / │
│  + livres  │                              │  commentaires  │
└────────────┴──────────────────────────────┴───────────────┘
```
Le rail et le panneau latéral sont escamotables ; en mode focus, la zone de
travail occupe 100 %.

**Tablette (600–1240)** — rail de 72 px (icônes seules) + zone de travail ;
le panneau devient une feuille modale.

**Mobile (< 600)** — barre de navigation basse (4 onglets : Bureau, Bibliothèque,
Écrire, Compte) ; les panneaux deviennent des feuilles modales à mi-hauteur ;
l'éditeur occupe tout l'écran ; la navigation *inside* l'éditeur passe par une
barre d'outils basse flottante.

### 9.3 Rythme vertical

Titre de section → 24 px → contenu. Contenu → 16 px → contenu voisin.
Un bloc de statut (`banner`) → 16 px → contenu.

---

## 10. Composants

Liste complète dans `packages/limpid_design_system/lib/src/components/`.
Contrat commun à **tous** les composants :

- taille de hit-test **≥ 44 × 44 px** (boutons, icônes cliquables)
- **focus visible** : anneau de 2 px `accent` + 2 px de décalage, jamais
  supprimé
- `Semantics` : chaque widget interactif expose un `label` et un `role`
  corrects ; les widgets purement décoratifs sont exclus de l'arbre sémantique
- **état désactivé** : opacité 0,45 + `cursor: not-allowed`, jamais une couleur
  différente qui ressemblerait à un état actif
- **état chargement** : le bouton conserve sa largeur (pas de saut de mise en
  page), le libellé est remplacé par un spinner et le `label` sémantique devient
  « Traitement en cours »

### 10.1 Boutons

| Variante | Fond | Texte | Bordure | Usage |
|---|---|---|---|---|
| `primary` | `accent` | `fgOnAccent` | — | Action principale, une seule par écran |
| `secondary` | `bgSurface` | `fgDefault` | `borderDefault` | Action courante |
| `ghost` | transparent | `fgDefault` | — | Action tertiaire, toolbar |
| `danger` | `danger` | `#FFFFFF` | — | Action destructrice |
| `text` | transparent | `accent` | — | Lien, action tertiaire dans un paragraphe |

Tailles : `sm` (hauteur 32) · `md` (40) · `lg` (48). Le bouton `lg` est la
taille par défaut sur mobile.

### 10.2 Champs de formulaire

Hauteur 40 (compact) / 48 (par défaut) / 56 (mobile). Bordure `borderDefault`,
focus `accent` 1 px + anneau. Label toujours **au-dessus** du champ (jamais
placeholder en guise de label). Message d'erreur sous le champ, en `danger`,
accompagné d'une icône. Champ en lecture seule : `bgSunken` + texte `fgMuted`,
pas de bordure.

### 10.3 Cartes

Un rayon = une élévation = un rôle. Une carte de projet utilise `radiusXl`,
`elevation1` et une bordure `borderSubtle` — pas les trois à la fois.

### 10.4 États

`LimpidEmptyState` : illustration (trait, 2 couleurs max) + titre + phrase
d'explication + **une** action principale + **une** action secondaire
(texte). Le vide est un écran dessiné, pas une page blanche.

---

## 11. Spécificités produit

### 11.1 Éditeur de manuscrit

- Fond = `bgCanvas`, pas `bgSurface` : le manuscrit est la page.
- Largeur 65 signes, centrée.
- Typography `Literata` 18/32 ; presets : *Confort* (18/32), *Dense* (16/28),
  *Écran* (16/26), *Typographique* (20/38).
- Sélecteur de ligne active : `accentSubtle` (pas d'accent plein, ça fatigue).
- Curseur de texte : `accent`.
- Bloc en cours de focus (mode focus) : tout le reste à 45 % d'opacité.
- Poignée de glissement : apparaît au survol, 24×24, `borderDefault` + `bgRaised`.
- Commentaire ancré : soulignement pointillé `secondary` ; survol → fond
  `secondarySubtle`.

### 11.2 Panneau IA

Fond `bgSurface`, bordure gauche `secondary` 2 px. Les suggestions inline sont
présentées en **différentiel** : suppressions en `danger` rayé, ajouts en
`success` souligné, jamais un simple texte. Chaque suggestion a trois actions :
*Appliquer*, *Ignorer*, *Regénérer*.

### 11.3 Synchronisation

Pastille de statut, jamais un texte seul :
`Synchronisé` (trait `success`), `Synchronisation…` (rotateur `accent`),
`Hors ligne — 4 modifications en attente` (icône `warning` + compte),
`Conflit résolu` (icône `info`).

### 11.4 Couverture

Ratio 2:3 (livre) et 1:1 (réseau). Le rectangle de couverture utilise
`radiusXs` (2 px) pour évoquer la tranche imprimée, pas `radiusXl`.

---

## 12. Accessibilité (WCAG 2.2 AA)

| Critère | Exigence |
|---|---|
| Contraste | 4,5:1 texte courant · 3:1 grand texte, icônes, focus |
| Cibles tactiles | ≥ 44 × 44 px, écart ≥ 8 px |
| Focus | Visible au clavier, jamais `outline: none` sans remplacement |
| Navigation clavier | Tous les contrôles, ordre logique, `Escape` ferme les surfaces |
| Lecteur d'écran | `Semantics` sur chaque widget ; ordre de lecture = ordre visuel |
| Animation | Respecte `prefers-reduced-motion` |
| Statuts | Couleur + icône + texte |
| Zoom | Utilisable jusqu'à 200 % sans perte de contenu ni défilement horizontal |
| Cible | Lien explicite (« Ouvrir le chapitre 3 »), pas « cliquez ici » |
| Formulaires | Label explicite, instructions avant l'erreur, résumé des erreurs en tête |

**Tests obligatoires** : NVDA + Firefox, VoiceOver + Safari, Keyboard-only sur
tous les parcours critiques, axe DevTools sur chaque écran.

---

## 13. Internationalisation

- `fr-FR` par défaut, `en-US` complet.
- Format de date et de nombre : `Intl`. Espace insécable fine entre nombre et
  unité (« 12 400 mots », « 3 h 20 »).
- Les chaînes ne sont jamais interpolées à la main : `context.l10n.xxx(count)`.
- Les mots comptés sont **invariables** (« 1 mot », « 0 mot »).
- Le texte des boutons d'action commence par un verbe à l'infinitif
  (« Enregistrer », « Publier », « Exporter »), pas par « Vous allez… ».

---

## 14. Ton de l'interface

- On s'adresse à l'auteur en **vous** sobre, sans familiarité forcée.
- Messages d'erreur : **ce qui s'est passé + comment corriger**.
  ✅ « L'export EPUB a échoué : le chapitre 4 contient un lien vers une image absente. Joignez l'image ou retirez le lien. »
  ❌ « Une erreur s'est produite. »
- Boutons : verbe d'action + objet si nécessaire. « Enregistrer », « Exporter en EPUB », « Publier ».
- Aucune exclamation superflue. Aucune emoji dans l'interface produit.
- Les nombres sont exacts, jamais « environ 1 000 » quand on peut compter.

---

## 15. Interdits

| Interdit | Raison |
|---|---|
| Couleur littérale dans un écran | Dérive du design system |
| `google_fonts` | Casse le hors-ligne et le premier rendu |
| Rayon qui change selon l'état | Rupture visuelle |
| Texte justifié dans l'interface | Rivages irréguliers |
| Émoji comme icône | Incohérent, non accessible |
| Statut codé par la couleur seule | Exclusion des daltoniens |
| Gradient sur les surfaces de formulaire | Lisibilité |
| Ombre portée seule en thème nuit | Invisible sur fond sombre |
| Animation > 400 ms | Ralentit |
| `outline: none` sans focus de remplacement | Inaccessible au clavier |
| Texte < 11 px | Illisible |
| Ombre portée + bordure forte + fond coloré sur une même carte | Hiérarchie plate |

---

## Annexe A — Correspondance Dart

```dart
final accent = Theme.of(context).colorScheme.primary;        // accent
final subtle = Theme.of(context).extension<LimpidColors>()!.accentSubtle;
final gap = Theme.of(context).extension<LimpidSpacing>()!.md; // 12
```

Les widgets `Limpid*` sont les seules surfaces d'API : un écran ne construit
jamais un `BoxDecoration` à la main.

## Annexe B — Export `tokens.json`

`packages/limpid_design_system/tokens.json` est généré à partir des constantes
Dart et sert de source pour Figma (via Tokens Studio), les maquettes HTML et
les tests de parité. **Il ne doit jamais être édité à la main** : toute
divergence est un bug, détecté par `test/tokens_parity_test.dart`.
