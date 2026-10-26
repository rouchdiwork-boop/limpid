const fs = require('fs');
const h = fs.readFileSync('limpid-mockups.html', 'utf8');
const i = h.indexOf('<script>'), j = h.lastIndexOf('</' + 'script>');
let src = h.slice(i + 8, j).split('   RENDU')[0].replace(/\/\* =+\s*$/, '');
const S = new Function('const window={__syncState:"online"};' + src + '\nreturn SCREENS;')();
const VOID = new Set(['br','img','input','hr','meta','link','source','area','col','embed','param','track','wbr']);
let total = 0;
for (const s of S) {
  const html = s.html();
  const stack = [];
  const problems = [];
  const re = /<(\/?)([a-zA-Z][\w-]*)((?:"[^"]*"|'[^']*'|[^"'>])*?)(\/?)>|<!--[\s\S]*?-->/g;
  let m;
  while ((m = re.exec(html)) !== null) {
    if (m[0].startsWith('<!--')) continue;
    const closing = m[1] === '/', tag = m[2].toLowerCase(), selfClose = m[4] === '/';
    if (VOID.has(tag) || selfClose) continue;
    if (!closing) { stack.push({ tag, at: m.index }); continue; }
    let k = -1;
    for (let n = stack.length - 1; n >= 0; n--) if (stack[n].tag === tag) { k = n; break; }
    if (k < 0) { problems.push(`</${tag}> sans ouverture`); continue; }
    if (k !== stack.length - 1) {
      const popped = stack.slice(k + 1).map(e => e.tag).join(' < ');
      problems.push(`</${tag}> ferme <${popped}> (position ${m.index})`);
      total += problems.length;
    }
    stack.length = k;
  }
  if (stack.length) { problems.push('non fermé: ' + stack.map(e => e.tag).join(' > ')); total += problems.length; }
  if (problems.length) { console.log('\n### ' + s.id); problems.slice(0, 6).forEach(p => console.log('   - ' + p)); }
}
console.log('\nTOTAL PROBLEMES: ' + total);

process.exit(total === 0 ? 0 : 1);
