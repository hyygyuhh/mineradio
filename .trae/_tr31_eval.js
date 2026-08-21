(() => {
  const s = document.getElementById('praise');
  if (!s) return JSON.stringify({ ok: false, reason: 'no praise section' });
  const walker = document.createTreeWalker(s, NodeFilter.SHOW_TEXT, null);
  let t = ''; let node;
  while ((node = walker.nextNode())) {
    const v = (node.nodeValue || '').trim();
    if (v) t += v + '\n';
  }
  const codes = [];
  for (let i = 0; i < t.length; i++) {
    const code = t.charCodeAt(i);
    if (code >= 0x4e00 && code <= 0x9fff) codes.push(t.charAt(i));
  }
  return JSON.stringify({
    ok: codes.length === 0,
    count: codes.length,
    sample: codes.slice(0, 30).join(''),
    preview: t.slice(0, 400),
  });
})()
