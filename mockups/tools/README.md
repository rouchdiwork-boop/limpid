# Outils de contrôle des maquettes

Ces scripts servent à **vérifier** `../limpid-mockups.html` — ils ne font pas
partie du produit. Ils ont servi à détecter deux fautes de balisage HTML qui
détruisaient la mise en page de l'éditeur.

Prérequis : Node 18+ et Playwright.

```bash
npm install -g playwright && npx playwright install chromium
```

Playwright est résolu automatiquement par `_playwright.js` : installation locale,
puis `node_modules`, puis cache npx.

## Scripts

| Script | Rôle |
|---|---|
| `check-html.js` | Valide l'imbrication des balises de **tous** les écrans et signale les fermetures croisées. C'est le contrôle qui a révélé les deux bugs. |
| `check-colors.js` | Signale toute couleur en dur dans le HTML d'un écran. La couleur vient toujours d'une variable CSS : une littérale ne fonctionne que dans un thème. |
| `trace-tags.js <id>` | Trace l'imbrication d'un écran précis et affiche la pile d'éléments au moment de l'anomalie. |
| `capture-screens.js` | Rend les 25 écrans dans `shot-<id>.png` et vérifie la structure DOM, les débordements et les erreurs JavaScript. |
| `capture-variant.js` | Capture la variante « Nuit + hors ligne » (`shot-night-offline.png`). |
| `measure-layout.js <#id>` | Mesure la géométrie réelle des zones d'un écran (rail, colonne, panneau) pour diagnostiquer un problème de mise en page. |

## Usage

```bash
cd mockups
node tools/check-html.js
node tools/check-colors.js
node tools/trace-tags.js editor-write
node tools/capture-screens.js
node tools/measure-layout.js '#editor-write'
```

## Règle à retenir

Après **toute** modification des maquettes, relancer `check-html.js` puis
`capture-screens.js`. Un `</div>` qui ferme un `<span>` ne lève aucune erreur
JavaScript : le parseur HTML referme silencieusement le parent, et l'écran se
déstructure sans le moindre message.
