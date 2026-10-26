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
