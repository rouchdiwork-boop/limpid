const { loadPlaywright } = require('./_playwright');
const { chromium } = loadPlaywright();
const fs = require('fs');
(async () => {
  const ids = [];
  const h = fs.readFileSync('limpid-mockups.html', 'utf8');
  const i = h.indexOf('<script>'), j = h.lastIndexOf('</' + 'script>');
  const src = h.slice(i + 8, j).split('   RENDU')[0].replace(/\/\* =+\s*$/, '');
  const S = new Function('const window={__syncState:"online"};' + src + '\nreturn SCREENS;')();
  S.forEach(s => ids.push(s.id));
  const browser = await chromium.launch();
  const page = await browser.newPage({ viewport: { width: 1600, height: 1000 } });
  const errors = [];
  page.on('pageerror', e => errors.push('PAGEERROR ' + e.message));
  page.on('console', m => { if (m.type() === 'error') errors.push('CONSOLE ' + m.text()); });
  await page.goto('file:///D:/Applications/Limpid/mockups/limpid-mockups.html', { waitUntil: 'load' });
  await page.waitForTimeout(1200);
  const report = [];
  for (const id of ids) {
    await page.evaluate((h) => { location.hash = h; }, id);
    await page.waitForTimeout(280);
    const m = await page.evaluate(() => {
      const row = document.querySelector('.app-row');
      const frame = document.querySelector('.frame');
      const kids = row ? [...row.children] : [];
      const fr = frame.getBoundingClientRect();
      const overflow = [...document.querySelectorAll('.frame *')].some(e => e.getBoundingClientRect().right > fr.right + 2);
      return { title: document.querySelector('#scr-title').textContent, kids: kids.map(c => c.className || c.tagName), frameH: Math.round(fr.height), overflow };
    });
    report.push(`${id.padEnd(15)} h=${String(m.frameH).padStart(4)} kids=[${m.kids.join(' | ')}]${m.overflow ? '  !! OVERFLOW' : ''}`);
    await page.screenshot({ path: `shot-${id}.png` });
  }
  console.log(report.join('\n'));
  console.log(errors.length ? '\nERRORS:\n' + errors.slice(0, 8).join('\n') : '\nNO JS ERRORS');
  await browser.close();
})();
