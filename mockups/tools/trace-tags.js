const fs = require('fs');
const h = fs.readFileSync('limpid-mockups.html', 'utf8');
const i = h.indexOf('<script>'), j = h.lastIndexOf('</' + 'script>');
let src = h.slice(i + 8, j).split('   RENDU')[0].replace(/\/\* =+\s*$/, '');
const S = new Function('const window={__syncState:"online"};' + src + '\nreturn SCREENS;')();
const VOID = new Set(['br','img','input','hr','meta','link','source','area','col','embed','param','track','wbr']);
const id = process.argv[2];
const html = S.find(s => s.id === id).html();
const stack = []; const re = /<(\/?)([a-zA-Z][\w-]*)((?:"[^"]*"|'[^']*'|[^"'>])*?)(\/?)>/g;
let m, ev = 0;
while ((m = re.exec(html)) !== null) {
  const closing = m[1] === '/', tag = m[2].toLowerCase();
  if (VOID.has(tag) || m[4] === '/') continue;
  ev++;
  if (!closing) { stack.push({ tag, at: m.index, ev }); continue; }
  let k = -1;
  for (let n = stack.length - 1; n >= 0; n--) if (stack[n].tag === tag) { k = n; break; }
  if (k < 0) {
    console.log(`EV ${ev} UNMATCHED </${tag}>  stack=[${stack.map(e => e.tag + '@' + e.ev).join(',')}]`);
    console.log('   context: ' + html.slice(Math.max(0, m.index - 200), m.index + 12).replace(/\s+/g, ' '));
  } else {
    if (k !== stack.length - 1) console.log(`EV ${ev} OVERCLOSE </${tag}> pops [${stack.slice(k + 1).map(e => e.tag + '@' + e.ev).join(',')}]`);
    stack.length = k;
  }
}
console.log('FINAL stack:', stack.map(e => e.tag + '@' + e.ev).join(' > '));
