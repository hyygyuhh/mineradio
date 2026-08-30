/**
 * Injected into Mineradio pages (MAIN world). Speaks the same postMessage protocol
 * as the Chrome extension content-bridge, but routes API calls through native host.
 */
(function () {
  var BRIDGE_SOURCE = 'mineradio-extension-bridge';
  var PAGE_SOURCE = 'mineradio-web-page';
  var desk = window.mineradioDesktop;
  if (!desk || !desk.invokeApi) return;

  var BRIDGE_VERSION = desk.version || '1.4.2';
  var EXT_ID = desk.extId || 'mineradio-ios';
  var PROXY_UA =
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36';

  if (window.__mineradioBridgeInjected) {
    window.postMessage(
      {
        source: BRIDGE_SOURCE,
        type: 'MINERADIO_BRIDGE_READY',
        version: BRIDGE_VERSION,
        extId: EXT_ID,
      },
      '*'
    );
    window.postMessage(
      {
        source: BRIDGE_SOURCE,
        type: 'MINERADIO_BRIDGE_PONG',
        ready: true,
        version: BRIDGE_VERSION,
        extId: EXT_ID,
      },
      '*'
    );
    return;
  }
  window.__mineradioBridgeInjected = true;
  window.__mineradioBridgeExtId = EXT_ID;
  try {
    localStorage.setItem('mineradio-bridge-ext-id', EXT_ID);
  } catch (_) {}

  function proxyRefererFor(url) {
    if (/qqmusic|gtimg|qpic|qlogo|y\.qq|imgcache\.qq/i.test(url)) return 'https://y.qq.com/';
    if (/kugou/i.test(url)) return 'https://www.kugou.com/';
    return 'https://music.163.com/';
  }

  function needsPrivilegedProxy(url) {
    return /(?:gtimg\.cn|qpic\.cn|qlogo\.cn|y\.qq\.com|qqmusic\.qq\.com|imgcache\.qq\.com)/i.test(
      String(url || '')
    );
  }

  function postToPage(payload, transfer) {
    window.postMessage(Object.assign({ source: BRIDGE_SOURCE }, payload), '*', transfer || []);
  }

  function arrayBufferToDataUrl(buffer, contentType) {
    if (!buffer || !buffer.byteLength) return '';
    var bytes = new Uint8Array(buffer);
    var parts = [];
    var step = 0x8000;
    for (var i = 0; i < bytes.length; i += step) {
      parts.push(String.fromCharCode.apply(null, bytes.subarray(i, i + step)));
    }
    var mime = String(contentType || 'image/jpeg').split(';')[0].trim() || 'image/jpeg';
    if (!/^image\//i.test(mime)) mime = 'image/jpeg';
    return 'data:' + mime + ';base64,' + btoa(parts.join(''));
  }

  function toArrayBuffer(buffer) {
    if (!buffer) return null;
    if (buffer instanceof ArrayBuffer) return buffer;
    if (ArrayBuffer.isView(buffer)) {
      return buffer.buffer.slice(buffer.byteOffset, buffer.byteOffset + buffer.byteLength);
    }
    if (buffer.type === 'Buffer' && Array.isArray(buffer.data)) {
      return new Uint8Array(buffer.data).buffer;
    }
    if (Array.isArray(buffer)) return new Uint8Array(buffer).buffer;
    return null;
  }

  function postBinaryResult(id, result, path) {
    if (path === '/api/cover' && result) {
      var readyDataUrl =
        result.dataUrl && /^data:image\//i.test(result.dataUrl) ? result.dataUrl : '';
      var ab = toArrayBuffer(result.buffer);
      if (!readyDataUrl && ab) {
        try {
          readyDataUrl = arrayBufferToDataUrl(ab, result.contentType);
        } catch (_) {}
      }
      if (readyDataUrl) {
        postToPage({
          type: 'MINERADIO_API_RESPONSE',
          id: id,
          ok: true,
          data: {
            __binary: true,
            status: result.status || 200,
            contentType: result.contentType || 'image/jpeg',
            dataUrl: readyDataUrl,
          },
        });
        return;
      }
    }

    var buffer = toArrayBuffer(result && result.buffer);
    var transfer = buffer ? [buffer] : [];
    var data = result;
    if (buffer && result) {
      data = Object.assign({}, result, { buffer: buffer });
    }
    postToPage(
      {
        type: 'MINERADIO_API_RESPONSE',
        id: id,
        ok: true,
        data: data,
      },
      transfer
    );
  }

  function postBinaryError(id, err) {
    postToPage({
      type: 'MINERADIO_API_RESPONSE',
      id: id,
      ok: false,
      error: (err && err.message) || String(err || 'proxy failed'),
    });
  }

  async function fetchBinaryInPage(payload) {
    var query = payload.query || {};
    var targetUrl = query.url;
    if (!targetUrl) throw new Error('Missing url');
    var extraHeaders =
      payload.headers && typeof payload.headers === 'object' ? payload.headers : {};
    var resp = await fetch(targetUrl, {
      method: payload.method || 'GET',
      headers: Object.assign(
        {
          'User-Agent': PROXY_UA,
          Referer: proxyRefererFor(targetUrl),
        },
        extraHeaders
      ),
    });
    if (!resp.ok) throw new Error('proxy fetch failed: ' + resp.status);
    var buffer = await resp.arrayBuffer();
    if (!buffer || !buffer.byteLength) throw new Error('proxy fetch empty body');
    return {
      __binary: true,
      status: resp.status,
      contentType: resp.headers.get('content-type') || 'application/octet-stream',
      buffer: buffer,
    };
  }

  async function fetchBinaryViaHost(payload) {
    var response = await desk.invokeApi(payload);
    if (!response || !response.ok) {
      throw new Error((response && response.error) || 'Background proxy failed');
    }
    var result = response.data;
    if (!result || !result.__binary) {
      throw new Error('Background proxy empty body');
    }
    var buffer = toArrayBuffer(result.buffer);
    if ((!buffer || !buffer.byteLength) && result.dataUrl) {
      return result;
    }
    if (!buffer || !buffer.byteLength) throw new Error('Background proxy empty body');
    return Object.assign({}, result, { buffer: buffer });
  }

  async function fetchBinaryWithFallback(payload) {
    var targetUrl = (payload && payload.query && payload.query.url) || '';
    var preferBg =
      needsPrivilegedProxy(targetUrl) || (payload && payload.path === '/api/cover');
    if (preferBg) {
      try {
        return await fetchBinaryViaHost(payload);
      } catch (bgErr) {
        try {
          return await fetchBinaryInPage(payload);
        } catch (_) {
          throw bgErr;
        }
      }
    }
    try {
      return await fetchBinaryInPage(payload);
    } catch (err) {
      return fetchBinaryViaHost(payload);
    }
  }

  async function forwardApi(id, payload) {
    try {
      var response = await desk.invokeApi(payload);
      var result = response && response.data;
      var buffer = result && toArrayBuffer(result.buffer);
      var transfer = [];
      var data = result;
      if (buffer) {
        data = Object.assign({}, result, { buffer: buffer });
        transfer.push(buffer);
      }
      postToPage(
        {
          type: 'MINERADIO_API_RESPONSE',
          id: id,
          ok: !!(response && response.ok),
          data: data,
          error: response && response.error,
        },
        transfer
      );
    } catch (err) {
      postToPage({
        type: 'MINERADIO_API_RESPONSE',
        id: id,
        ok: false,
        error: (err && err.message) || String(err),
      });
    }
  }

  window.addEventListener('message', function (event) {
    if (event.source !== window) return;
    var data = event.data;
    if (!data || data.source !== PAGE_SOURCE) return;

    if (data.type === 'MINERADIO_BRIDGE_PING' || data.type === 'MINERADIO_BRIDGE_PROBE') {
      try {
        desk.ensureMediaRules && desk.ensureMediaRules();
      } catch (_) {}
      postToPage({
        type: 'MINERADIO_BRIDGE_PONG',
        ready: true,
        version: BRIDGE_VERSION,
        extId: EXT_ID,
      });
      return;
    }

    if (data.type === 'MINERADIO_API') {
      var id = data.id;
      var payload = data.payload || {};
      var path = payload.path || '';
      if (path === '/api/audio' || path === '/api/cover') {
        fetchBinaryWithFallback(payload)
          .then(function (result) {
            postBinaryResult(id, result, path);
          })
          .catch(function (err) {
            postBinaryError(id, err);
          });
        return;
      }
      forwardApi(id, payload);
    }
  });

  postToPage({
    type: 'MINERADIO_BRIDGE_READY',
    version: BRIDGE_VERSION,
    extId: EXT_ID,
  });
  try {
    desk.ensureMediaRules && desk.ensureMediaRules();
  } catch (_) {}
})();
