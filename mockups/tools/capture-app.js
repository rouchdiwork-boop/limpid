/**
 * Capture l'application Limpid servie en local (build web de release).
 *
 *   node mockups/tools/capture-app.js [url] [sortie.png]
 *
 * Le script attend que l'interface soit rendue — Flutter web ne paint rien
 * tant que le moteur n'a pas téléchargé CanvasKit — puis enregistre la
 * capture et signale les erreurs de console.
 */
const path = require('path');
const { loadPlaywright } = require('./_playwright');

const url = process.argv[2] || 'http://127.0.0.1:8090/';
const output = process.argv[3] || path.join(__dirname, '..', 'shot-app.png');

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

  // Flutter rend dans un canvas : on attend que la scène soit peinte.
  await page.waitForSelector('flutter-view, flt-glass-pane, canvas', { timeout: 60000 });
  await page.waitForTimeout(6000);

  await page.screenshot({ path: output, fullPage: false });
  console.log(`Capture : ${output}`);
  console.log(`Titre : ${await page.title()}`);
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
