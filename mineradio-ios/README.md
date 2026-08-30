# mineradio-ios

iOS / iPadOS 客户端：基于 `WKWebView` 的浏览器，内置 **Mineradio Bridge**。
与 Android 端架构一致，仅「宿主」不同（隐藏 WKWebView + 原生 Cookie / HTTP）。

- 版本：**1.0.0** · Bridge：**1.4.2**
- 最低系统：iOS 15.0
- Bundle ID：`art.mineradio.browser`

## 功能

- 多标签、后退 / 前进 / 刷新 / 主页
- 地址栏搜索（无 `://` 且含 `.` 视为网址，否则 Bing 回退）
- 标签 favicon（Google s2 服务）
- 顶栏折叠（顶部边缘下拉手势恢复）
- 网易 / QQ / 酷狗快捷登录
- Bridge 状态指示 + 离线点击重试
- 长按关闭标签

## 架构

```
mineradio.art 页面
    │  postMessage（MINERADIO_* 协议）
    ▼
inject.js（页面注入层，与 Android 共用）
    ▼
runner.html + bridge/api/*（Bridge host：chrome.* polyfill）
    ▼
MineradioHost（webkit messageHandlers）→ 原生 Cookie + URLSession
```

各端差异仅在宿主。Bridge 的 `api/router.js` / `netease.js` / `qq.js` /
`kugou.js` / `cookies.js` / `weather.js` 与扩展、Android 完全一致，由
`sync-bridge.sh` 从 `Mineradio-Bridge-1.4.1/` 同步进来。

### iOS 宿主的关键设计

iOS 的 `WKScriptMessageHandler` 是异步的，无法像 Android `@JavascriptInterface`
那样同步返回。`Resources/host/runner.html` 用一个 **JS 内存镜像** 解决：

- `getCookie(url)`：从 `window.__mineradioCookies`（原生通过
  `__mineradioCookieSync` 预同步 + `WKHTTPCookieStoreObserver` 持续推送）按
  domain/path/secure 计算同步返回。
- `storageGetAll()`：从 `window.__mineradioStorage` 同步返回（启动时从
  `UserDefaults` 注入）。
- `setCookie` / `storageSet` / `startHttp`：`postMessage` 到原生，副作用型；
  镜像乐观更新。

`window.fetch` 被 polyfill 为走原生 `URLSession`（可设 Cookie、可读
Set-Cookie，QQ 扫码登录所需），结果经 `__nativeHttpResult` 回调。

## 本地开发（Mac）

### 1. 安装工具

```bash
brew install xcodegen
```

### 2. 同步 Bridge 资源

```bash
./mineradio-ios/scripts/sync-bridge.sh
```

把 `Mineradio-Bridge-1.4.1/` 同步到 `Resources/bridge/`，刷新 `host/inject.js`，
复制 1024 图标到 `Assets.xcassets`。

### 3. 生成工程并打开

```bash
cd mineradio-ios
xcodegen generate
open MineRadioWeb.xcodeproj
```

### 4. 运行

选择模拟器，`Cmd+R`。Bridge host 加载 `mineradio-bridge://app/host/runner.html`，
顶栏 `Bridge 1.4.2` 变绿即就绪。

## 使用注意

1. **必须在 App 内**登录网易云 / QQ / 酷狗，Cookie 才会被 Bridge 读到
   （所有 WebView 共享 `WKWebsiteDataStore.default()`）。
2. 折叠顶栏后，从屏幕顶部边缘下拉可恢复。
3. Bridge 离线时点击顶栏 `Bridge 未就绪` 重试。

## 同步 Bridge（升级后必做）

```bash
./mineradio-ios/scripts/sync-bridge.sh
```

`host/runner.html` 是 iOS 专属宿主，**不会被同步覆盖**。
