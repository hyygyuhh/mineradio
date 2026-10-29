/**
 * Mineradio 全站统计
 * - baidu / clarity：已接入
 * - ga4：填入真实 Measurement ID（形如 G-XXXXXXXXXX）后自动加载
 *   获取：https://analytics.google.com → 管理 → 数据流 → 测量 ID
 */
(function () {
  var cfg = window.MR_ANALYTICS || {
    baidu: '78f7b7ba65689eaeae9e9a7e4b796704',
    clarity: 'y5df0zq3wk',
    ga4: ''
  };
  window.MR_ANALYTICS = cfg;

  // —— 百度统计 ——
  if (cfg.baidu) {
    window._hmt = window._hmt || [];
    (function () {
      var hm = document.createElement('script');
      hm.src = 'https://hm.baidu.com/hm.js?' + cfg.baidu;
      var s = document.getElementsByTagName('script')[0];
      s.parentNode.insertBefore(hm, s);
    })();
  }

  // —— Microsoft Clarity ——
  if (cfg.clarity) {
    (function (c, l, a, r, i, t, y) {
      c[a] = c[a] || function () { (c[a].q = c[a].q || []).push(arguments); };
      t = l.createElement(r); t.async = 1; t.src = 'https://www.clarity.ms/tag/' + i;
      y = l.getElementsByTagName(r)[0]; y.parentNode.insertBefore(t, y);
    })(window, document, 'clarity', 'script', cfg.clarity);
  }

  // —— Google Analytics 4 ——
  var ga4 = (cfg.ga4 || '').trim();
  var ga4Ready = /^G-[A-Z0-9]+$/i.test(ga4);
  window.MR_GA4_READY = ga4Ready;
  if (ga4Ready) {
    var gtagScript = document.createElement('script');
    gtagScript.async = true;
    gtagScript.src = 'https://www.googletagmanager.com/gtag/js?id=' + ga4;
    document.head.appendChild(gtagScript);
    window.dataLayer = window.dataLayer || [];
    window.gtag = function () { window.dataLayer.push(arguments); };
    window.gtag('js', new Date());
    window.gtag('config', ga4, {
      anonymize_ip: true,
      page_path: location.pathname + location.search
    });
  } else if (ga4) {
    console.warn('[Mineradio] GA4 ID 格式无效，应为 G-XXXXXXXXXX，当前：', ga4);
  }

  // —— IndexNow：通知 Bing / Yandex 等当前页可抓 ——
  try {
    var indexNowKey = '447cd2c000f248cc84cbc2415f3ee4af';
    var indexNowUrl = encodeURIComponent(location.href.split('#')[0]);
    var indexNowImg = new Image();
    indexNowImg.src =
      'https://api.indexnow.org/indexnow?url=' + indexNowUrl + '&key=' + indexNowKey;
  } catch (e) {}

  // —— 邮箱：拆开写进 data-mr-mail，避免 Cloudflare Email Obfuscation；点击用捕获处理，避免 href="#" 回顶 ——
  function mrMailFromEl(el) {
    var parts = String((el && el.getAttribute('data-mr-mail')) || '').split('|');
    if (parts.length < 2) return '';
    var user = parts[0].trim();
    var domain = parts[1].trim();
    if (!user || !domain) return '';
    return user + '@' + domain;
  }
  window.MR_fillMails = function (root) {
    root = root || document;
    var nodes = root.querySelectorAll('[data-mr-mail]');
    for (var i = 0; i < nodes.length; i++) {
      var el = nodes[i];
      var email = mrMailFromEl(el);
      if (!email) continue;
      el.setAttribute('href', 'mailto:' + email);
      if (el.getAttribute('data-mr-mail-label') !== '1') {
        el.textContent = email;
      }
    }
  };
  document.addEventListener(
    'click',
    function (e) {
      var el = e.target && e.target.closest ? e.target.closest('[data-mr-mail]') : null;
      if (!el) return;
      var email = mrMailFromEl(el);
      if (!email) return;
      e.preventDefault();
      e.stopPropagation();
      window.location.href = 'mailto:' + email;
    },
    true
  );
  function scheduleFillMails() {
    try { window.MR_fillMails(); } catch (e) {}
  }
  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', scheduleFillMails);
  } else {
    scheduleFillMails();
  }
  setTimeout(scheduleFillMails, 0);
  setTimeout(scheduleFillMails, 400);
  setTimeout(scheduleFillMails, 1200);

  // —— 回到顶部 ——
  function initToTop() {
    if (document.getElementById('mr-totop')) return;
    if (!document.getElementById('mr-totop-css')) {
      var style = document.createElement('style');
      style.id = 'mr-totop-css';
      style.textContent =
        '#mr-totop{position:fixed;right:22px;bottom:28px;z-index:70;width:44px;height:44px;border:1px solid rgba(255,255,255,.14);border-radius:14px;background:rgba(10,12,20,.78);color:#f5f5f7;backdrop-filter:blur(12px);-webkit-backdrop-filter:blur(12px);display:grid;place-items:center;cursor:pointer;opacity:0;visibility:hidden;pointer-events:none;transform:translateY(10px);transition:opacity .28s ease,transform .28s cubic-bezier(.22,1,.36,1),visibility .28s,background .2s,border-color .2s,color .2s;box-shadow:0 10px 28px rgba(0,0,0,.28)}' +
        '#mr-totop.is-show{opacity:1;visibility:visible;pointer-events:auto;transform:none}' +
        '#mr-totop:hover{background:rgba(216,236,63,.92);border-color:rgba(216,236,63,.95);color:#111113}' +
        '#mr-totop:focus-visible{outline:2px solid #d8ec3f;outline-offset:3px}' +
        '#mr-totop svg{display:block;width:18px;height:18px}' +
        '@media (max-width:720px){#mr-totop{right:16px;bottom:20px;width:42px;height:42px;border-radius:12px}}' +
        '@media (prefers-reduced-motion:reduce){#mr-totop{transition:none}}';
      document.head.appendChild(style);
    }
    var btn = document.createElement('button');
    btn.id = 'mr-totop';
    btn.type = 'button';
    btn.setAttribute('aria-label', '回到顶部');
    btn.title = '回到顶部';
    btn.innerHTML =
      '<svg viewBox="0 0 24 24" aria-hidden="true" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"><path d="M6 14l6-6 6 6"/></svg>';
    document.body.appendChild(btn);
    var reduce = false;
    try {
      reduce = window.matchMedia('(prefers-reduced-motion: reduce)').matches;
    } catch (e) {}
    function sync() {
      btn.classList.toggle('is-show', window.scrollY > 420);
    }
    window.addEventListener('scroll', sync, { passive: true });
    sync();
    btn.addEventListener('click', function () {
      try {
        if (typeof trackEvent === 'function') trackEvent('back_to_top', { category: 'Nav' });
      } catch (e) {}
      window.scrollTo({ top: 0, behavior: reduce ? 'auto' : 'smooth' });
    });
  }
  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', initToTop);
  } else {
    initToTop();
  }

  // —— 统一事件 ——
  window.trackEvent = function (eventName, params) {
    params = params || {};
    try {
      if (typeof _hmt !== 'undefined') {
        _hmt.push([
          '_trackEvent',
          params.category || 'General',
          eventName,
          params.label || '',
          typeof params.value === 'number' ? params.value : 0
        ]);
      }
    } catch (e) {}
    try {
      if (typeof gtag === 'function' && window.MR_GA4_READY) {
        gtag('event', eventName, params);
      }
    } catch (e) {}
    try {
      if (typeof clarity !== 'undefined') {
        if (clarity.event) clarity.event(eventName);
        if (clarity.set && params) {
          Object.keys(params).forEach(function (k) {
            try { clarity.set(k, String(params[k])); } catch (e) {}
          });
        }
      }
    } catch (e) {}
  };
})();
