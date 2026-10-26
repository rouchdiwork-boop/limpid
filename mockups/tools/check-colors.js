/**
 * Vérifie qu'aucun écran ne porte de couleur en dur.
 *
 *   node mockups/tools/check-colors.js [id ...]
 *
 * La règle de la maison : la couleur d'un écran vient toujours d'une
 * variable CSS (`--p-*` pour le produit, `--pg-*` pour le chrome de page).
 * Une couleur littérale ne fonctionne que dans un thème — l'écran casse
 * dans les trois autres.
 *
 * Deux exceptions, volontairement tolérées :
 *
 *   - la palette des couvertures (`.p-cover.cN`) porte les 24 valeurs de la
 *     palette produit : 6 teintes × 4 thèmes ;
 *   - les pastilles des thèmes (réglages) et le voile de la palette de
 *     commandes montrent le chrome de la page, pas le produit.
 */
const fs = require('fs');
const path = require('path');

const FILE = path.join(__dirname, '..', 'limpid-mockups.html');
const mockups = fs.readFileSync(FILE, 'utf8');

/** Les classes dont la couleur est déjà portée par le thème. */
const TOKENISED = /\.p-cover\.c[1-6]\b/;

/** Les littéraux de couleur cherchés dans le HTML d'un écran. */
const LITERAL = /#[0-9A-Fa-f]{3,8}\b|\b(?:rgba?|hsla?)\([^)]*\)/g;

/** Les écrans dont les littéraux sont tolérés, avec la raison. */
const EXEMPT = {
  settings: 'les pastilles montrent le fond des quatre thèmes',
  command: 'le voile de la palette de commandes est du chrome de page',
};

/**
 * Les écrans de la maquette, évalués depuis le script du document.
 *
 * @returns {Array<{id: string, html: () => string}>}
 */
function screens() {
  const start = mockups.indexOf('<script>');
  const end = mockups.lastIndexOf('</' + 'script>');
  const source = mockups
    .slice(start + 8, end)
    .split('   RENDU')[0]
    .replace(/\/\* =+\s*$/, '');
  return new Function(
    'const window={__syncState:"online"};' + source + '\nreturn SCREENS;',
  )();
}

/**
 * Les littéraux de couleur d'un écran, hors classes tokenisées.
 *
 * @param {string} html Le HTML rendu de l'écran.
 * @returns {string[]} Les littéraux trouvés.
 */
function literalsOf(html) {
  const found = [];
  let match;
  LITERAL.lastIndex = 0;
  while ((match = LITERAL.exec(html)) !== null) {
    const before = html.slice(Math.max(0, match.index - 80), match.index);
    const className = before.split('class="').pop();
    if (className && TOKENISED.test(className)) continue;
    found.push(match[0]);
  }
  return found;
}

const wanted = process.argv.slice(2);
const list = screens().filter(
  (s) => wanted.length === 0 || wanted.includes(s.id),
);

let total = 0;
for (const screen of list) {
  const literals = literalsOf(screen.html());
  if (!literals.length) continue;
  if (EXEMPT[screen.id]) {
    console.log(`--- ${screen.id} : toléré (${EXEMPT[screen.id]})`);
    continue;
  }
  total += literals.length;
  console.log(`### ${screen.id}`);
  [...new Set(literals)].forEach((l) => console.log(`   - ${l}`));
}

console.log('\nCOULEURS EN DUR : ' + total);
process.exit(total === 0 ? 0 : 1);
