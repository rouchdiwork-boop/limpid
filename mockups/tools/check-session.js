/**
 * Vérifie que la session de démonstration s'ouvre dans le navigateur.
 *
 *   node mockups/tools/check-session.js [url]
 *
 * Le script remplit le formulaire de connexion, envoie le lien, puis attend
 * le bureau. Une capture est enregistrée à la fin.
 */
const path = require('path');
const { loadPlaywright } = require('./_playwright');

const url = process.argv[2] || 'http://127.0.0.1:8090/';

(async () => {
  const playwright = loadPlaywright();
  const browser = await playwright.chromium.launch({
    args: ['--use-gl=swiftshader', '--enable-unsafe-swiftshader'],
  });
  const page = await browser.newPage({ viewport: { width: 1440, height: 900 } });

  const errors = [];
  page.on('console', (message) => {
    if (message.type() === 'error') errors.push(message.text());
  });
  page.on('pageerror', (error) => errors.push(String(error)));

  await page.goto(url, { waitUntil: 'load', timeout: 60000 });
  await page.waitForSelector('flutter-view, flt-glass-pane, canvas', { timeout: 60000 });
  await page.waitForTimeout(5000);

  // Flutter web dessine dans un canvas : les champs ne sont pas des
  // éléments du DOM. On clique donc à la position du champ, puis on écrit.
  await page.mouse.click(720, 496);
  await page.waitForTimeout(500);
  await page.keyboard.type('auteur@exemple.fr');
  await page.waitForTimeout(800);

  // Le bouton du lien d'accès, à sa position dans la maquette.
  await page.mouse.click(720, 563);
  await page.waitForTimeout(8000);

  await page.screenshot({ path: path.join(__dirname, '..', 'shot-session.png') });
  console.log('Capture : mockups/shot-session.png');
  console.log('URL après connexion :', page.url());
  if (errors.length > 0) {
    console.log('Erreurs de console :');
    errors.forEach((error) => console.log(`  - ${error}`));
  } else {
    console.log('Aucune erreur de console.');
  }

  await browser.close();
})().catch((error) => {
  console.error(error);
  process.exit(1);
});
