# Contributing à Limpid

Merci de votre intérêt. Ce document décrit comment proposer une
contribution. Les règles techniques complètes sont dans
[`docs/PROMPT.md`](docs/PROMPT.md) ; l'outillage est dans
[`docs/DEVELOPMENT.md`](docs/DEVELOPMENT.md).

---

## Avant de commencer

1. **Lire [`docs/DECISIONS.md`](docs/DECISIONS.md).** Chaque décision y est
   contraignante. Une contribution qui contredit une décision existante doit
   d'abord la faire évoluer, par une nouvelle entrée datée.
2. **Choisir un lot.** Le projet est livré en huit lots
   ([`docs/ROADMAP.md`](docs/ROADMAP.md)). Une contribution se rattache à un
   lot ; une contribution qui n'y se rattache pas est une proposition
   distincte, à discuter avant d'écrire du code.
3. **Ouvrir une issue** pour les changements d'architecture, les nouvelles
   dépendances ou les changements de format.

## Mise en place

```bash
flutter --version   # Flutter 3.44.4
dart --version      # Dart 3.12.2

bash tool/bootstrap.sh   # ou : powershell -File tool/bootstrap.ps1
bash tool/check.sh       # vérifie que la base est verte
```

## Règles de code

Ces règles sont issues de `docs/PROMPT.md` (§ 8) et des règles générales du
projet.

### Immuabilité

Jamais de mutation d'un objet existant : toujours une nouvelle instance. Les
objets Dart sont `final` par défaut.

```dart
// Wrong
project.title = 'Nouveau titre';

// Right
final updated = project.copyWith(title: 'Nouveau titre');
```

### Simplicité

- **KISS** : la solution la plus simple qui fonctionne.
- **DRY** : une logique répétée est extraite ; pas d'abstraction spéculative.
- **YAGNI** : pas de functionality avant qu'elle ne soit nécessaire.

### Organisation

| Règle | Valeur |
|---|---|
| Taille d'un fichier | 200 à 400 lignes, 800 au maximum |
| Organisation | Par *feature*, pas par *type* |
| Taille d'une fonction | Moins de 50 lignes, une seule responsabilité |
| Imbrication | Préférer les retours précoces, maximum 4 niveaux |

### Nommage

| Élément | Convention | Exemple |
|---|---|---|
| Variables, fonctions | `camelCase` | `chapterTitle` |
| Types, widgets | `PascalCase` | `ChapterEditor` |
| Constantes | `UPPER_SNAKE_CASE` | `MAX_SCENE_WORDS` |
| Booléens | Préfixe `is`, `has`, `should`, `can` | `isOffline`, `hasUnsavedChanges` |
| Hooks | Préfixe `use` | `useChapterAutosave` |

### Erreurs et validation

- Aucune exception avalée : pas de `catch (e) {}` vide. Un `AsyncError` typé
  porte un message utilisateur, le serveur journalise le détail.
- Toute entrée est validée à la frontière : JSON entrant, paramètres, formulaires.
- Zéro `dynamic` non typé au-delà de la couche de parsing.
- Les requêtes SQL sont paramétrées, jamais concaténées.

### Interface

- Interface en français par défaut, `en-US` complet ; aucune chaîne en dur.
- Le design system est du code : `LimpidTheme.of(context)` et les widgets
  `Limpid*`. Aucune couleur, aucun `TextStyle` littéral dans un écran.
- Accessibilité WCAG 2.2 AA : cibles ≥ 44 px, focus visible, `Semantics` sur
  chaque widget interactif, contraste 4,5:1.

## Tests

Toute fonctionnalité est livrée **avec ses tests**. Une pull request sans
test est incomplète.

| Type | Cible | Emplacement |
|---|---|---|
| Unitaires | ≥ 80 % sur `limpid_core` | `test/` du paquet |
| Convergence CRDT | 100 % — fuzz multi-agents | `packages/limpid_core/test/sync/` |
| Widgets | ≥ 70 % | `apps/limpid_app/test/` |
| Golden | Composants du design system | `packages/limpid_design_system/test/` |
| E2E | Parcours critiques | `apps/limpid_app/integration_test/` |

La convergence du CRDT est la propriété la plus importante du produit : tout
changement dans `limpid_core` doit faire passer le fuzz test.

## Workflow

1. Branche : `feat/<lot>-<sujet>`, `fix/<sujet>`, `chore/<sujet>`,
   `docs/<sujet>`.
2. Commits petits et conventionnels :

   ```text
   <type>: <description>
   ```

   Types : `feat`, `fix`, `refactor`, `docs`, `test`, `chore`, `perf`, `ci`.
3. Pull request ouverte **dès que la fonctionnalité est démontrable**.
4. La CI doit être verte : `analyze` → `test` → builds.
5. La Definition of Done est cochée dans le modèle de pull request.

### Definition of Done

- [ ] `flutter analyze` : 0 erreur, 0 avertissement
- [ ] `dart format --set-exit-if-changed .` : propre
- [ ] Tests verts (unitaires + widget + fuzz sync)
- [ ] Aucun `TODO` / `FIXME` non justifié
- [ ] Fonctionnement hors-ligne vérifié pour le périmètre annoncé
- [ ] Écrans valides dans les quatre thèmes
- [ ] Navigation clavier et lecteur d'écran vérifiés
- [ ] Textes i18n (aucune chaîne en dur)
- [ ] Documentation à jour dans `docs/`

## Dépendances

Toute nouvelle dépendance doit justifier son coût (taille, maintenance,
alternative écartée) **dans la pull request**. Une dépendance sans
justification n'est pas acceptée.

## Documentation

- Une décision d'architecture nouvelle → `docs/DECISIONS.md`, datée, numérotée.
- Un changement de procedure → `docs/DEVELOPMENT.md`.
- Un changement de périmètre fonctionnel → `docs/FEATURE_MATRIX.md`.

## Licence

En contribuant, vous acceptez que votre contribution soit publiée sous la
licence MIT du dépôt ([`LICENSE`](LICENSE)).
