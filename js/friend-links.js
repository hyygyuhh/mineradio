/*! Mineradio friend links — edit LINKS to update footer 友情链接 */
(function () {
  var LINKS = [
    { name: '酷狗 WAVE', url: 'https://wave.kugou.com/' }
  ];

  function ensureStyles() {
    if (document.getElementById('mr-friend-links-css')) return;
    var css = document.createElement('style');
    css.id = 'mr-friend-links-css';
    css.textContent =
      '.foot-friends{display:flex;flex-wrap:wrap;align-items:baseline;gap:10px 18px;margin-top:22px;padding-top:18px;border-top:1px solid rgba(255,255,255,.06);font-size:13px;line-height:1.6}' +
      '.foot-friends-label{flex:none;color:#6e6e76;font-size:12px;font-weight:600;letter-spacing:.08em}' +
      '.foot-friends a{color:#8e8e96;text-decoration:none;transition:color .2s}' +
      '.foot-friends a:hover{color:#f5f5f7}' +
      '.foot-friends-apply{color:#6e6e76;font-size:12px}' +
      '.foot-friends-apply a{color:#6e6e76;border-bottom:1px solid rgba(255,255,255,.14);text-decoration:none}' +
      '.foot-friends-apply a:hover{color:#f5f5f7}';
    document.head.appendChild(css);
  }

  function render(root) {
    if (!root || root.getAttribute('data-mr-friends-ready') === '1') return;
    var frag = document.createDocumentFragment();
    var label = document.createElement('span');
    label.className = 'foot-friends-label';
    label.textContent = '友情链接';
    frag.appendChild(label);

    LINKS.forEach(function (item) {
      if (!item || !item.url || !item.name) return;
      var a = document.createElement('a');
      a.href = item.url;
      a.target = '_blank';
      a.rel = 'noopener noreferrer';
      a.textContent = item.name;
      frag.appendChild(a);
    });

    var apply = document.createElement('span');
    apply.className = 'foot-friends-apply';
    apply.innerHTML = '申请友链：<a href="mailto:support@mineradio.cn?subject=' +
      encodeURIComponent('申请友情链接') + '">support@mineradio.cn</a>';
    frag.appendChild(apply);

    root.textContent = '';
    root.appendChild(frag);
    root.setAttribute('data-mr-friends-ready', '1');
  }

  function boot() {
    ensureStyles();
    document.querySelectorAll('[data-mr-friends]').forEach(render);
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', boot);
  } else {
    boot();
  }
})();
