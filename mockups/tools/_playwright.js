/**
 * Résolution de Playwright pour les scripts de contrôle des maquettes.
 *
 * Playwright n'est pas une dépendance du projet : il est utilisé uniquement
 * pour vérifier le rendu. On essaie donc, dans l'ordre :
 *   1. `playwright` installé dans le dépôt (node_modules) ;
 *   2. `playwright` resolvable depuis le répertoire courant ;
 *   3. le cache npx de la machine.
 *
 * Pour installer Playwright globalement :
 *   npm install -g playwright && npx playwright install chromium
 */
const path = require('path');
const fs = require('fs');
const { execSync } = require('child_process');

/** Renvoie les emplacements possibles du cache npm, du plus probable au moins probable. */
function cacheRoots() {
  const roots = [];
  const push = (value) => {
    if (value && !roots.includes(value)) roots.push(value);
  };

  push(process.env.npm_config_cache);
  try {
    push(execSync('npm config get cache', { encoding: 'utf8', stdio: ['ignore', 'pipe', 'ignore'] }).trim());
  } catch (error) {
    // npm absent : on continue avec les variables d'environnement
  }
  push(path.join(process.env.LOCALAPPDATA || '', 'npm-cache'));
  push(path.join(process.env.APPDATA || '', 'npm-cache'));
  push(path.join(process.env.HOME || '', '.npm'));
  return roots;
}

function loadPlaywright() {
  const attempts = [];

  try {
    return require('playwright');
  } catch (error) {
    attempts.push('require("playwright")');
  }

  for (const root of cacheRoots()) {
    const npxRoot = path.join(root, '_npx');
    if (!fs.existsSync(npxRoot)) continue;
    for (const entry of fs.readdirSync(npxRoot)) {
      const candidate = path.join(npxRoot, entry, 'node_modules', 'playwright');
      if (!fs.existsSync(candidate)) continue;
      try {
        return require(candidate);
      } catch (error) {
        attempts.push(candidate);
      }
    }
  }

  throw new Error(
    'Playwright est introuvable. Installes-le avec ' +
    '`npm install -g playwright && npx playwright install chromium`.\n' +
    'Tentatives : ' + attempts.join(', '),
  );
}

module.exports = { loadPlaywright };
