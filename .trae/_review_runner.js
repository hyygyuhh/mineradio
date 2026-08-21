// 沙箱本地 agent-browser 浏览器自动化：复审所有 TR rubric
const base = 'http://127.0.0.1:8765/index.html';
const { spawnSync } = require('child_process');
const fs = require('fs');
const OUT = '/tmp/review_runs';
fs.mkdirSync(OUT, { recursive: true });

function run(script, name) {
  const scriptPath = `${OUT}/${name}.mjs`;
  fs.writeFileSync(scriptPath, script);
  // 启动时使用 --disable-web-security 等 flag，让本地 file:// 也能跨域执行；这里直接使用 http:// URL
  // 用 `agent-browser shell --script <file>` 方式跑
  const res = spawnSync('agent-browser', ['shell', '--file', scriptPath], {
    timeout: 180_000,
    stdio: ['ignore', 'pipe', 'pipe'],
    env: { ...process.env },
  });
  const stdout = (res.stdout || '').toString();
  const stderr = (res.stderr || '').toString();
  const combined = '===STDOUT===\n' + stdout + '\n===STDERR===\n' + stderr + '\n===EXIT===' + res.status;
  fs.writeFileSync(`${OUT}/${name}.log`, combined);
  return { stdout, stderr, status: res.status, combined, path: `${OUT}/${name}.log` };
}

const r1_script = `
// TR-1.1 + TR-1.2 + TR-5.1
await page.goto('${base}', { waitUntil: 'networkidle', timeout: 60000 });
await page.waitForTimeout(1200);

// TR-1.2
const t12 = await page.evaluate(() => {
  const btn = document.querySelector('button[data-i18n="foot_clog"]');
  return btn && btn.getAttribute && btn.getAttribute('type') === 'button' ? { ok: true, type: btn.getAttribute('type') } : { ok:false, html: btn?.outerHTML?.slice(0,300) };
});
console.log('TR-1.2', JSON.stringify(t12));

// TR-5.1：console.warning/error 含 {{ x }} never resolved？
const t51_before = await page.evaluate(() => {
  window.__tr51 = [];
  const ptw = console.warn.bind(console); const pte = console.error.bind(console); const pti = console.info.bind(console);
  console.warn = (...a)=>{ window.__tr51.push('W:'+a.join(' ')); ptw(...a); };
  console.error=(...a)=>{ window.__tr51.push('E:'+a.join(' ')); pte(...a); };
  console.info =(...a)=>{ window.__tr51.push('I:'+a.join(' ')); pti(...a); };
  return 'ok';
});
await page.waitForTimeout(1200);

// TR-1.1 click changelog
const beforeClick = await page.evaluate(() => !!document.querySelector('[data-clog-mask]'));
console.log('TR-1.1 before clog mask visible =', beforeClick);
// 先找 footer changelog button ref
const refsBefore = await page.refs();
console.log('TR-1.1 refs total =', Object.keys(refsBefore).length);
const clogBtn = await page.evaluate(() => {
  const b = document.querySelector('button[data-i18n="foot_clog"]');
  if (!b) return { found:false };
  const r = b.getBoundingClientRect();
  return { found:true, text: b.textContent?.slice(0,40), x: r.x, y: r.y, w: r.width, h: r.height };
});
console.log('TR-1.1 clogBtn =', JSON.stringify(clogBtn));

await page.evaluate(()=>{
  const b = document.querySelector('button[data-i18n="foot_clog"]');
  if (b) { const evt = new MouseEvent('click',{bubbles:true,cancelable:true}); b.dispatchEvent(evt); }
});
await page.waitForTimeout(1500);

const t11 = await page.evaluate(() => {
  const mask = Array.from(document.querySelectorAll('*')).find(n => n.getAttribute && n.getAttribute('data-clog-mask') !== null);
  const visible = mask && mask.getBoundingClientRect().width > 0;
  const anchor = mask ? mask.querySelector('a[href="https://github.com/XxHuberrr/Mineradio/releases"]') : null;
  return { maskFound: !!mask, maskVisible: !!visible, targetBlank: anchor ? anchor.target === '_blank' : false, hasRel: anchor ? /noreferrer/.test(anchor.rel||'') : false, text: anchor?.textContent?.trim()?.slice(0,60) };
});
console.log('TR-1.1', JSON.stringify(t11));

// TR-5.1 累计日志检索
const t51 = await page.evaluate(() => {
  const joined = (window.__tr51 || []).join('\\n');
  const hit = joined.includes('{{ x }} never resolved') ? (joined.match(/\\{\\{ x \\}\\} never resolved/g) || []).length : 0;
  return { hitCount: hit, tail: joined.split('\\n').slice(-30).join('\\n') };
});
console.log('TR-5.1', JSON.stringify(t51));
await page.screenshot({ path: '${OUT}/tr1.png', fullPage:false });
`;

const r2_script = `
// TR-3.1 EN 模式下评价区无中文字符
await page.goto('${base}', { waitUntil: 'networkidle', timeout: 60000 });
await page.waitForTimeout(1500);
// 点语言切换：找 EN 按钮
const info = await page.evaluate(() => {
  const btns = Array.from(document.querySelectorAll('button, a, [role="button"]'));
  const en = btns.find(b => (b.textContent||'').trim().includes('EN') && /lang|toggle|switch|i18n/.test(b.className + ' ' + b.outerHTML) )
    || btns.find(b => (b.textContent||'').trim() === 'EN');
  return { enBtn: !!en, enText: en?.textContent?.slice(0,50), enHtml: en?.outerHTML?.slice(0,400) };
});
console.log('TR-3.1 EN btn info:', JSON.stringify(info));

// 若未找到按钮，通过内部 state setState：调用 applyLang 设置 L='en'
const setStateRes = await page.evaluate(() => {
  try {
    // window.__mr... 是根 root 注入？尝试从组件找到 applyLang('en')
    const reactRoot = document.getElementById('root');
    // 根据 index.html：i18n 切换是 T.lang = 'en' / localStorage.setItem('i18n', 'en') + applyLang()
    // 我们直接模拟 set 并触发 applyLang
    if (typeof window !== 'undefined' && window.I18N) {
      // rootRef? 组件内 applyLang 方法
      // 尝试用脚本重新实现一遍 applyLang + L=en
      const T = window.I18N;
      const L = 'en';
      document.documentElement.setAttribute('lang', 'en');
      document.documentElement.setAttribute('data-locale', 'en');
      const root = document.getElementById('root');
      if (root) {
        root.querySelectorAll('[data-i18n]').forEach(el => {
          const key = el.getAttribute('data-i18n');
          if (T[key]) { const v = typeof T[key][L] === 'string' ? T[key][L] : T[key]['zh']; el.textContent = v; if (el.tagName === 'INPUT' || el.tagName === 'TEXTAREA') { el.value = v; } }
        });
        // 模板字符串属性：html
        root.querySelectorAll('[data-i18n-html]').forEach(el => {
          const key = el.getAttribute('data-i18n-html');
          if (T[key]) el.innerHTML = (typeof T[key][L] === 'string' ? T[key][L] : T[key]['zh']);
        });
        // title alt aria-label placeholder
        ['title','alt','aria-label','placeholder'].forEach(attr => {
          root.querySelectorAll(\`[data-i18n-\${attr}]\`).forEach(el => {
            const key = el.getAttribute('data-i18n-'+attr);
            if (T[key]) el.setAttribute(attr, typeof T[key][L] === 'string' ? T[key][L] : T[key]['zh']);
          });
        });
      }
      return 'manual applied';
    }
    return 'no window.I18N';
  } catch(e) { return 'err:'+String(e); }
});
console.log('TR-3.1 setState applied res:', setStateRes);
await page.waitForTimeout(600);

const tr31 = await page.evaluate(() => {
  const sec = document.getElementById('praise');
  if (!sec) return { ok:false, reason: 'no #praise section' };
  // aria-hidden 副本也要算；取可见文本
  const walker = document.createTreeWalker(sec, NodeFilter.SHOW_TEXT, null);
  let txt = '';
  while (true) { const n = walker.nextNode(); if (!n) break; const s = (n.nodeValue || '').trim(); if (s) txt += s + '\\n'; }
  const re = /[\\u4e00-\\u9fff]/g;
  const m = txt.match(re) || [];
  return { ok: m.length === 0, chineseCount: m.length, sample: m.slice(0,30).join(''), preview: txt.slice(0,400) };
});
console.log('TR-3.1 result:', JSON.stringify(tr31));
await page.screenshot({ path: '${OUT}/tr3.png', fullPage:false });
`;

const r3_script = `
// TR-4.1 / TR-4.2 中文 hash -> 英文锚点映射
const samples = [
  { from: '#功能',  expect: 'features' },
  { from: '#下载',  expect: 'download' },
  { from: '#评价',  expect: 'praise'   },
  { from: '#资助我们', expect: 'support' },
];
const results = [];
for (const s of samples) {
  await page.goto('${base}' + encodeURI(s.from), { waitUntil: 'networkidle', timeout: 60000 });
  await page.waitForTimeout(1400);
  const url = page.url();
  const evalRes = await page.evaluate((expect) => {
    const hash = window.location.hash;
    const el = document.getElementById(expect);
    const rect = el ? el.getBoundingClientRect() : null;
    const top = rect ? rect.top : null;
    return { hash, elFound: !!el, top };
  }, s.expect);
  results.push({ sample: s, urlHash: decodeURIComponent(url.split('#')[1] || ''), ...evalRes, ok: /#(?:%23)?(.+)$/.exec(url) && decodeURIComponent(url.split('#')[1]||'') === s.expect && evalRes.elFound && evalRes.top <= 100 });
}
console.log('TR-4.x', JSON.stringify(results, null, 2));
`;

const r1 = run(r1_script, 't1_t5');
console.log('== T1 + T5 完成 status=' + r1.status + ' 日志: ' + r1.path);
console.log(r1.stdout.split('\n').slice(-60).join('\n'));
console.log('---STDERR T1_T5---\n', (r1.stderr || '').split('\n').slice(-20).join('\n'));

const r2 = run(r2_script, 't3');
console.log('== T3 完成 status=' + r2.status + ' 日志: ' + r2.path);
console.log(r2.stdout.split('\n').slice(-80).join('\n'));

const r3 = run(r3_script, 't4');
console.log('== T4 完成 status=' + r3.status + ' 日志: ' + r3.path);
console.log(r3.stdout.split('\n').slice(-80).join('\n'));

// 汇总
const summary = {
  t1_t5_log: r1.path, t3_log: r2.path, t4_log: r3.path,
  t1_status: r1.status, t3_status: r2.status, t4_status: r3.status,
};
fs.writeFileSync(`${OUT}/summary.json`, JSON.stringify(summary, null, 2));
console.log('SUMMARY AT', `${OUT}/summary.json`);
