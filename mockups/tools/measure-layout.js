const { loadPlaywright } = require('./_playwright');
const { chromium } = loadPlaywright();
(async () => {
  const target = process.argv[2] || '#editor-write';
  const browser = await chromium.launch();
  const page = await browser.newPage({ viewport: { width: 1600, height: 1000 } });
  const errors = [];
  page.on('console', m => { if (m.type() === 'error') errors.push(m.text()); });
  page.on('pageerror', e => errors.push('PAGEERROR ' + e.message));
  await page.goto('file:///D:/Applications/Limpid/mockups/limpid-mockups.html' + target, { waitUntil: 'load' });
  await page.waitForTimeout(2500);
  const data = await page.evaluate(() => {
    const r = (s) => {
      const e = document.querySelector(s);
      if (!e) return s + ' = MISSING';
      const b = e.getBoundingClientRect();
      const cs = getComputedStyle(e);
      return `${s.padEnd(16)} x=${Math.round(b.x)} w=${Math.round(b.width)} h=${Math.round(b.height)} dir=${cs.flexDirection} disp=${cs.display} flex=${cs.flex}`;
    };
    const row = document.querySelector('.app-row');
    return {
      frame: r('.frame'), row: r('.app-row'), outline: r('.p-outline'),
      editor: r('.col.grow'), panel: r('.p-panel.ai'), toolbar: r('.p-toolbar'),
      manuscript: r('.p-manuscript'),
      rowChildren: row ? [...row.children].map(c => c.className + ' (' + Math.round(c.getBoundingClientRect().x) + ')') : []
    };
  });
  console.log(JSON.stringify(data, null, 1));
  if (errors.length) console.log('ERRORS:', errors.slice(0, 5));
  await page.screenshot({ path: '_pw_' + (process.argv[3] || 'shot') + '.png' });
  await browser.close();
})();
