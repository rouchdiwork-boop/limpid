const { loadPlaywright } = require('./_playwright');
const { chromium } = loadPlaywright();
(async () => {
  const b = await chromium.launch();
  const p = await b.newPage({ viewport: { width: 1600, height: 1000 } });
  await p.goto('file:///D:/Applications/Limpid/mockups/limpid-mockups.html#editor-review', { waitUntil: 'load' });
  await p.waitForTimeout(1500);
  await p.click('#seg-product button[data-product="night"]');
  await p.waitForTimeout(400);
  await p.click('#seg-sync button[data-sync="offline"]');
  await p.waitForTimeout(400);
  await p.screenshot({ path: 'shot-night-offline.png' });
  await b.close();
})();
