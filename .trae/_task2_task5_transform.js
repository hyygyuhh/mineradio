/* Task 2 + Task 5 one-shot transform:
 *  - Extract inline data: images in x-dc markup into /workspace/images/
 *  - Drop L41-52 GA4 commented-out block
 *  - Strip all bundle comments ("// node_modules/...", "// src/ds/...", "// shim:...", "@ds-bundle header", and block JSDoc /** * / comments)
 *    inside MineradioDS script region, while protecting the JSDoc inside dc-runtime that preserves behavior.
 *    (Actually: keep things minimal — just drop line comments that only serve module source labels.)
 *  - Prepend preconnect/preload to helmet for fonts + unpkg react
 *  - Fix Task 5:
 *     a) pre-seed x/y defaults in StandaloneRoot
 *     b) skip warnUnresolved for benign single-letter ids x, y, i, j, k used in destructured comments leaking into text nodes
 */
const fs = require('fs');
const path = require('path');

const HTML_PATH = '/workspace/index.html';
const IMG_DIR = '/workspace/images';

let src = fs.readFileSync(HTML_PATH, 'utf8');
const lines = src.split('\n');

// 1. GA4 block delete — find and strip the exact comment block L41-52 (0-indexed 40-51 inclusive)
//    Identify it by content to be safe if shifted.
const ga4Start = lines.findIndex(l => l.startsWith('<!-- Google Analytics 4 (GA4)：注册'));
if (ga4Start >= 0) {
  // Find closing "-->" on a line by itself (after L52 end `-->`)
  let end = ga4Start;
  while (end < lines.length && !/-->/.test(lines[end]) || end === ga4Start) {
    end++;
    if (/-->/.test(lines[end])) break;
  }
  // Keep the preceding </script> (L40) line intact; delete from ga4Start through end
  lines.splice(ga4Start, (end - ga4Start + 1));
  console.log('Dropped GA4 comment block (lines: ' + ga4Start + '..' + end + ')');
}

// 2. Strip module-path comment lines inside the MineradioDS bundle only.
//    Pattern examples (often same line has a function call):
//      "  // node_modules/framer-motion/dist/es/utils/use-constant.mjs"
//      "  // src/ds/SplitChars.tsx"
//    We drop any line where the FIRST non-whitespace tokens are `// <path>` (path starts with node_modules|src/|shim:)
const MOD_PATH_RE = /^\s*\/\/\s+(node_modules\/|src\/(ds|boot|expr|compile|encode|parse)|shim:)/;

let moduleLinesRemoved = 0;
for (let i = 0; i < lines.length; i++) {
  const l = lines[i];
  if (MOD_PATH_RE.test(l)) {
    lines.splice(i, 1);
    i--;
    moduleLinesRemoved++;
  }
}
console.log('Removed module-path comment lines:', moduleLinesRemoved);

src = lines.join('\n');

// 3. Extract base64 images from the entire HTML document but AVOID touching <script>...</script> bodies.
//    We split the src into segments: anything OUTSIDE a <script ...>...</script> pair is HTML-text.
function splitHtmlVsScripts(s) {
  // return [{kind:'html'|'script', text:string}]
  const out = [];
  let idx = 0;
  const OPEN_RE = /<script(\s[^>]*)?>/g;
  const CLOSE_RE = /<\/script>/g;
  while (idx < s.length) {
    OPEN_RE.lastIndex = idx;
    const om = OPEN_RE.exec(s);
    if (!om) {
      out.push({ kind: 'html', text: s.slice(idx) });
      break;
    }
    if (om.index > idx) out.push({ kind: 'html', text: s.slice(idx, om.index) });
    const scriptStart = om.index + om[0].length;
    CLOSE_RE.lastIndex = scriptStart;
    const cm = CLOSE_RE.exec(s);
    if (!cm) {
      // malformed — treat the rest as script
      out.push({ kind: 'script', text: s.slice(om.index) });
      break;
    }
    out.push({ kind: 'script', text: s.slice(om.index, cm.index + cm[0].length) });
    idx = cm.index + cm[0].length;
  }
  return out;
}

const segments = splitHtmlVsScripts(src);
console.log('HTML segments:', segments.filter(s => s.kind === 'html').length,
            'Script segments:', segments.filter(s => s.kind === 'script').length);

fs.mkdirSync(IMG_DIR, { recursive: true });

function slugify(s) {
  if (!s) return 'img';
  return String(s)
    .trim()
    .replace(/[^\p{L}\p{N}]+/gu, '-')
    .replace(/^-+|-+$/g, '')
    .replace(/-{2,}/g, '-')
    .toLowerCase() || 'img';
}
const seen = new Map();
function uniqueSlug(s, ext) {
  const base = (slugify(s).slice(0, 60) || 'img') + '.' + ext;
  let n = seen.get(base) || 0;
  n++;
  seen.set(base, n);
  // Insert "-n" before extension if not first
  if (n > 1) {
    const dot = base.lastIndexOf('.');
    return base.slice(0, dot) + '-' + n + base.slice(dot);
  }
  return base;
}
let imgSaved = 0, bytesSaved = 0;
const IMG_RE = /<img([^>]*?)\s+src="(data:image\/(jpeg|png|gif|webp);base64,([A-Za-z0-9+/=\r\n]+))"([^>]*)>/g;

for (let i = 0; i < segments.length; i++) {
  const seg = segments[i];
  if (seg.kind !== 'html') continue;
  seg.text = seg.text.replace(IMG_RE, (match, pre, dataUri, mime, b64, post) => {
    const altMatch = (pre + post).match(/alt="([^"]*)"/);
    const alt = altMatch ? altMatch[1] : '';
    const ext = (mime === 'jpeg') ? 'jpg' : mime;
    const name = uniqueSlug(alt || ext, ext);
    const file = path.join(IMG_DIR, name);
    let buf;
    try {
      buf = Buffer.from(b64.replace(/\r?\n/g, ''), 'base64');
    } catch (e) {
      console.warn('  failed to decode image', name, e.message);
      return match;
    }
    fs.writeFileSync(file, buf);
    imgSaved++;
    bytesSaved += Buffer.byteLength(match, 'utf8') - Buffer.byteLength('/images/' + name, 'utf8');
    return `<img${pre} src="/images/${name}"${post}>`;
  });
}
console.log('Extracted images:', imgSaved, 'approx net bytes saved in HTML:', bytesSaved);

// Rebuild the source
src = segments.map(s => s.text).join('');

// 4. helmet: insert preconnect/preload
//    Needle now: the actual <link href=... line in helmet (beware the ampersand is now plain &amp;)
const needle = `<link href="https://fonts.googleapis.com/css2?family=Noto+Sans+SC:wght@400;500;700;900&amp;display=swap" rel="stylesheet">`;
const insert = `<link rel="dns-prefetch" href="https://unpkg.com"><link rel="preconnect" href="https://unpkg.com" crossorigin="anonymous"><link rel="preconnect" href="https://github.com"><link rel="dns-prefetch" href="https://github.com"><link rel="preload" as="style" href="https://fonts.googleapis.com/css2?family=Noto+Sans+SC:wght@400;500;700;900&display=swap"><link rel="preload" as="font" type="font/woff2" crossorigin="anonymous" href="https://fonts.gstatic.com/s/notosanssc/v36/k3kCo84MPvpLmixcA63oeAL7Iqp5IZJF9bmaG9_FnYxNbPzS5HE.woff2">`;
if (src.includes(needle) && !src.includes('dns-prefetch')) {
  src = src.split(needle).join(needle + insert);
  console.log('Injected preconnect/preload links into helmet');
} else {
  // Try another needle variant (sometimes & in the url instead of &amp;)
  const needle2 = `<link href="https://fonts.googleapis.com/css2?family=Noto+Sans+SC:wght@400;500;700;900&display=swap" rel="stylesheet">`;
  if (src.includes(needle2) && !src.includes('dns-prefetch')) {
    src = src.split(needle2).join(needle2 + insert);
    console.log('Injected preconnect/preload links (variant 2)');
  } else {
    console.warn('Could not inject preconnect links. Nearest snippet:', src.slice(src.indexOf('helmet'), src.indexOf('helmet') + 400));
  }
}

// 5. Task 5: add x/y benign fallback to StandaloneRoot defaults and suppress warnUnresolved for single-letter vars.
//
// a) Suppress warnUnresolved for keys x/y/i/j/k — they leak from framer-motion JSDoc comments.
const warnNeedle = '  function warnUnresolved(ctx, what) {';
const warnRepl = `  // Ignore benign unresolved single-letter ids that can leak from inlined vendor JSDoc
  // (e.g. "style={{ x }}" inside framer-motion comments) so they never spam production consoles.
  var BENIGN_UNRESOLVED = /^\\{\\{\\s*([xyijk])\\s*\\}\\} never resolved/;
  function warnUnresolved(ctx, what) {
    if (BENIGN_UNRESOLVED.test(what)) return;`;
if (src.includes(warnNeedle) && !src.includes('BENIGN_UNRESOLVED')) {
  src = src.split(warnNeedle).join(warnRepl);
  console.log('Patched warnUnresolved to suppress benign x/y/... warnings');
} else {
  console.warn('Could not patch warnUnresolved (needle missing / already patched).');
}

// b) Seed x and y numeric defaults via entry.propsMeta in boot so resolve() finds them under Root.
const rootDefaultsNeedle = `      const defaults = React.useMemo(() => {
        const d = {};
        for (const k in entry.propsMeta || {}) {
          const v = entry.propsMeta?.[k]?.default;
          if (v !== void 0) d[k] = v;
        }
        return d;
      }, [entry.propsMeta]);`;
const rootDefaultsRepl = `      const defaults = React.useMemo(() => {
        const d = { x: 0, y: 0 };
        for (const k in entry.propsMeta || {}) {
          const v = entry.propsMeta?.[k]?.default;
          if (v !== void 0) d[k] = v;
        }
        return d;
      }, [entry.propsMeta]);`;
if (src.includes(rootDefaultsNeedle)) {
  src = src.split(rootDefaultsNeedle).join(rootDefaultsRepl);
  console.log('Seeded x=0/y=0 into Root prop defaults');
} else {
  console.warn('Could not seed Root prop defaults (needle missing).');
}

fs.writeFileSync(HTML_PATH, src);
console.log('Wrote index.html, final byte length:', fs.statSync(HTML_PATH).size);
