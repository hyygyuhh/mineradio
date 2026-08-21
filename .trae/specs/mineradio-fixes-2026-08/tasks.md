# Mineradio 官网修复 - Implementation Plan

## Task 1: 更新日志 Modal 补齐 GitHub Releases CTA 链接 + 按钮可聚焦语义化
- **Status**: `pending`
- **Priority**: high
- **Depends On**: None
- **Description**:
  - 在 Modal DOM（`index.html` L578-591，`<sc-if value="{{ clogOpen }}">` 段）内，底部「关闭」按钮上方新增一行 CTA 链接 `View all releases on GitHub`，跳转 `https://github.com/XxHuberrr/Mineradio/releases`。
  - 在 `I18N` 对象内新增键 `clog_all: { zh: '在 GitHub 查看全部版本 →', en: 'View all releases on GitHub →' }`。
  - Footer「更新日志」按钮补 `type="button"`，确保键盘 Tab 可聚焦。
- **Acceptance Criteria Addressed**: AC-1、AC-8
- **Test Requirements**:
  - `rule` TR-1.1: 点击 Footer「更新日志」按钮后 1.5s 内，页面内出现 data-clog-mask 可见元素，且其中包含 `<a target="_blank" href="https://github.com/XxHuberrr/Mineradio/releases">` 的 DOM 节点。证据：agent-browser click + snapshot + eval 断言。
  - `rule` TR-1.2: Footer「更新日志」<button> 含有 `type="button"` 属性。证据：agent-browser eval `button.getAttribute('type') === 'button'`。
- **Notes**: 此前 headless 环境曾无法定位 @e31 按钮，疑似 snapshot ref 变更导致；本任务完成后改用 DOM 属性 / selector 断言。

## Task 2: 首页 index.html 体积瘦身（删除注释型膨胀内容）+ preconnect/preload 补齐 + 静态托管压缩配置
- **Status**: `pending`
- **Priority**: high
- **Depends On**: None
- **Description**:
  - 删除/压缩 3 类不参与运行时执行的注释内容：
    1. `MineradioDS` 大 bundle 顶部 1 行 JSON 注释 `/* @ds-bundle: {...} */`（≈ 4-5KB）。
    2. `<head>` L41-52 已被 `<!-- -->` 注释掉的 GA4 占位代码行（≈ 12 行），替换为一行 40 字以内占位注释说明。
    3. 运行时组件代码中 `framer-motion` 用法示例、注释解释块等长注释（详见搜索）。
  - 在 `<helmet>` 段（L232-234 附近）添加 6 条 NFR-2 指定 preconnect/preload link。
  - 新建 `/workspace/_headers`（Cloudflare Pages/Netlify 格式）：
    - `/index.html` 路径：`Cache-Control: no-cache`
    - `/*.js`、`/*.css`、`/*.woff2`、`/*.jpg`、`/*.png`、`/*.svg`：`Cache-Control: public, max-age=31536000, immutable`
    - 并在头部声明 Brotli/gzip 支持说明注释。
- **Acceptance Criteria Addressed**: AC-5、AC-6、AC-7
- **Test Requirements**:
  - `rule` TR-2.1: `wc -c /workspace/index.html` 返回字节数 ≤ 1,578,961（基线 1,754,401 的 90%）。
  - `rule` TR-2.2: `document.querySelectorAll('link[rel="preconnect"], link[rel="preload"]')` 中能检索到 6 条 NFR-2 精确 URL 各 ≥ 1 次。
  - `rule` TR-2.3: `/workspace/_headers` 文件存在，且 `grep -c 'no-cache'` ≥1、`grep -c 'immutable'` ≥1、`grep -c 'Brotli\|brotli\|Content-Encoding\|gzip'` ≥1。

## Task 3: 评价区硬编码中文改为 data-i18n，并补齐 I18N 中英翻译键
- **Status**: `pending`
- **Priority**: medium
- **Depends On**: None
- **Description**:
  - 为评价区前 7 张卡片的 `blockquote` 与 `figcaption` 各赋唯一 `data-i18n` key（`pr1_q` ~ `pr7_q` 为引文，`pr1_a` ~ `pr7_a` 为署名来源）。
  - aria-hidden 的跑马灯副本（第 8-14 张 figure）复用同 key。
  - 在 `I18N = { ... }` 对象（约 L629）中新增上述 14 个 key（7 引文 + 7 署名）的 zh/en 成对翻译：
    - 引文英文需忠实原义、风格自然，避免字面硬翻；
    - 署名英文：微博用户→Weibo user；B站 UP 主→Bilibili creator；B站用户→Bilibili user；酷安用户→Coolapk user；软件站编辑评测→Software site review；独立博客评测→Indie blog review。
  - `applyLang()` 方法已通用遍历 `[data-i18n]`，无需再改代码逻辑。
- **Acceptance Criteria Addressed**: AC-2、AC-8
- **Test Requirements**:
  - `rule` TR-3.1: 点击 EN 后，在 `document.getElementById('praise')` 的可见文本中执行中文正则 `/[\u4e00-\u9fff]/g` 检索，结果 count = 0。
  - `rule` TR-3.2: 再切回 zh，7 张 figure 的引文与署名文本与原硬编码完全一致（语义回归）。

## Task 4: 中文 hash → 英文锚点映射 + hashchange 事件监听
- **Status**: `pending`
- **Priority**: medium
- **Depends On**: None
- **Description**:
  - 在 `Component` 类内新增 `setup()` 方法的 hash 处理代码（或新增独立子方法 `setupHash()` 并在 setup 末尾调用）：
    1. 定义映射表常量 `HASH_MAP = { '功能':'features', '下载':'download', '评价':'praise', '资助':'support', '资助我们':'support', '首页':'top' }`。
    2. 定义 `_handleHash()` 方法：读 `location.hash` → `decodeURIComponent` → 若中文命中映射则 `replaceState` 到英文 hash 并 `scrollIntoView({behavior:'smooth', block:'start'})`；若英文 hash 命中 id 则保持不处理。
    3. 在 `componentDidMount` 中调用一次 `_handleHash()`；并 `window.addEventListener('hashchange', this._boundHandleHash)`，unmount 移除。
- **Acceptance Criteria Addressed**: AC-3、AC-8
- **Test Requirements**:
  - `rule` TR-4.1: agent-browser `open /workspace/index.html#功能` → `get url` 返回 hash 为 `#features`，且 `document.getElementById('features').getBoundingClientRect().top` ≤ 100。
  - `rule` TR-4.2: 「下载」「评价」「资助我们」三组 hash 同样映射成功（共 4 组样本）。

## Task 5: 定位并修复 `{{ x }} never resolved` 警告的 DC Root
- **Status**: `pending`
- **Priority**: low
- **Depends On**: None
- **Description**:
  - 搜索 index.html 模板树中独立 `{{ x }}` 的上下文（非 `style={{ x }}`、非 motion JSX 注释示例）。若不存在显式字面量，则在 renderVals 返回对象（L706-798）尾部为 key `x` 提供安全 fallback 值（空串 `''`）作为兜底。
  - 可选：若定位发现来源为某个未命名 hint-placeholder 的 `<sc-if>` / `<sc-for>`，为其补 `hint-placeholder-val="''"`。
- **Acceptance Criteria Addressed**: AC-4
- **Test Requirements**:
  - `rule` TR-5.1: 新首访 `agent-browser console` 输出的每条日志 message 字段 grep `{{ x }} never resolved` 次数 = 0。
