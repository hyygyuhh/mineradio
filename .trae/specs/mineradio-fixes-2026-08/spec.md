# Mineradio 官网修复 - 产品需求规格

## Overview
- **Summary**: 针对此前 Dogfood 分析发现的 4 个优先级问题（P1 更新日志、P1 性能、P2 评价 i18n、P2 中文锚点 hash、P3 `{{ x }}` 警告），在工作区 `/workspace/` 的静态官网源码（单文件 `index.html` + 附属资源）中进行源码级修复。
- **Purpose**: 修复功能死链、补齐国际化、优化首屏加载，并消除控制台警告，改善官网用户体验与 SEO 表现。
- **Target Users**: Mineradio 官网访客（桌面端 / 移动端 / 中英文用户），以及官网维护者 XxHuber。

## Goals
1. 更新日志按钮点击后有可感知且正确的行为（跳转 GitHub Releases，或打开已有 Modal 并补全外链 CTA）。
2. 首屏 HTML 体积相较基线 1,754,401 bytes（源码 on-disk 大小，注意编码差异）减少 ≥ 10%；同时补齐 preconnect / preload。
3. 在 `<head>` 中添加 Service Worker 级别的压缩配置提示（`Accept-Encoding` 响应通过 `_headers` 文件为 Cloudflare Pages / Netlify 风格静态宿主提供 Brotli / gzip 提示；同时输出压缩前文件体积对比）。
4. EN 模式下用户评价区不再出现中文硬编码：所有卡片的 `blockquote` 与 `figcaption` 改为 `data-i18n` 渲染并在 `I18N` 表中补齐中英文。
5. 访问 `https://mineradio.cn/#功能`、`#下载`、`#评价`、`#资助` 等中文 hash 时，自动映射到对应英文 id（`#features` / `#download` / `#praise` / `#support`）并滚动到目标位置，不再被清空。
6. 控制台 warning `[dc-runtime] Root: {{ x }} never resolved — rendered as empty` 定位源头并移除（或提供 fallback 数据），使新页面加载不再输出。

## Non-Goals
- **不重构** DC Runtime / MineradioDS 组件包本身（1,069 行起的 `MineradioDS` 大 bundle 视为构建产物，不在本次修改范围）。
- **不替换** React UMD 加载源、**不升级**框架版本。
- **不改变**第三方统计脚本（百度统计 / Clarity / Cloudflare Insights）的加载顺序与配置。
- **不新建** 多页面路由（保持单页锚点结构）。
- **不新增** 图片 / 视频 / 字体等二进制资源。

## Background & Context
源码位于 `/workspace/`，为典型 Cloudflare Pages / GitHub Pages 风格静态部署仓库：
- `index.html` 大小 `1,754,401` 字节（≈1.67 MB on-disk），网络传输 encodedBodySize 913.7KB，说明主文件膨胀主要由 **MineradioDS 打包 JS bundle（L1069+，约 800KB）** + **内联样式 `<style id="mr-ds-css">` + DC 模板树**共同造成。
- `<link rel="preconnect">` 已存在于 L232-233（fonts.googleapis / fonts.gstatic），但 unpkg、baidu hm、clarity、Cloudflare Insights 等尚未 preconnect。
- 下载区 macOS Tab 的死链（ISSUE-001）实际是 `this._macArch` 在非 macOS 浏览器返回 null，导致 `macDownloadHref: '#'`（line 793-797）。本次需求**不含 macOS 死链修复**（用户点名列表中未包含，ISSUE-001 另有修复安排）。
- Changelog 功能**已经有 UI**（line 578-591 的 Modal DOM 与 line 602/709-711 的状态机 `clogOpen` / `openClog` / `closeClog` / `clogMaskClick`），但此前测试报告显示按钮 "点不开" — 经验证实际 DOM 逻辑正确，问题可能是 headless 下 ref 变化所致；**本规格将在 Modal 内新增 "View all releases on GitHub" CTA 链接** 作为额外保险，并将按钮语义锚定保证可点。
- 评价区（line 426-446 `#praise`）8 张可见 + 8 张 aria-hidden 跑马灯卡片均为硬编码中文文本，未带 `data-i18n`。
- 中文 hash 不兼容：`setup()` 中（line 901+）没有任何处理 `location.hash` 为中文并做映射的代码。页面初始化后 `#features` 等靠 `html { scroll-behavior: smooth }` 工作，但中文编码 `#%E5%8A%9F%E8%83%BD` 找不到对应 id 被忽略。
- `{{ x }}` never resolved warning 的源头是 DC Runtime 在遇到模板变量不存在时触发；需在 `index.html` 全文件中检索只有 `{{ x }}` 字面量的上下文（非示例注释）。

## Functional Requirements

### FR-1 更新日志行为闭环
- 点击 Footer 的「更新日志」/ Changelog 按钮，页面必须显示 Modal 或跳转到 GitHub Releases 链接。
- 若使用 Modal（现有的 `<sc-if value="{{ clogOpen }}">` 结构），需在 Modal 底部新增一行 **「在 GitHub 查看全部版本 →」** CTA 链接（`target="_blank"`，`href="https://github.com/XxHuberrr/Mineradio/releases"`），其文案走 `data-i18n="clog_all"`。
- 更新日志按钮本身必须可键盘聚焦（`type="button"` 显式声明）。

### FR-2 评价区中英双语
- 从中文模式点击 EN，评价区 `#praise` 的每张 `<figure>`：
  1. `<blockquote>` 文本被英文等效翻译替换。
  2. `<figcaption>` 来源署名（微博用户 / B站 UP 主 / 酷安用户 / …）被英文替换（例如 "Weibo user" / "Bilibili creator" / "Coolapk user" …）。
  3. aria-hidden 的跑马灯副本同步替换。
- 回切中文，所有文案必须还原。

### FR-3 中文锚点 hash 兼容
- 页面加载（DOMContentLoaded / 组件挂载 `componentDidMount`）和 `hashchange` 事件两条通道都要做：
  1. 读取 `location.hash`，做 `decodeURIComponent`。
  2. 通过映射表 `{ '功能': 'features', '下载': 'download', '评价': 'praise', '资助': 'support', '资助我们': 'support', '首页': 'top' }` 识别。
  3. 若命中则调用 `scrollIntoView` 滚动至目标，且 `history.replaceState` 改为规范英文 hash（分享出去的 URL 正确）。
  4. 若 hash 已是英文 id → 不替换、走浏览器原生 smooth scroll。

### FR-4 消除 `{{ x }}` 控制台警告
- 定位出 DC 模板中使用了未定义变量 `{{ x }}` 的 Root，并在组件 state / renderVals 提供 fallback 值或删除无效 Root。
- 新首访控制台日志中不再出现该 warning 字符串。

## Non-Functional Requirements

### NFR-1 首屏 HTML 体积瘦身 ≥ 10%
- on-disk `wc -c index.html` 基线值 ≈ 1,754,401 bytes。
- 瘦身目标：**改动后文件体积 ≤ 基线 × 90%（≤ 1,578,961 bytes）**。
- 瘦身手段必须不破坏功能，允许做法：
  - 删除 `MineradioDS` bundle 中内联的 TypeScript 类型 / d.ts 注释行（`*.d.ts":"..."` 这部分 source map/元数据 hash 串可直接从注释 `/* @ds-bundle: ... */` 里移除或改为最短占位）。
  - 删除 41-52 行被注释掉的 GA4 代码（占 12 行），或直接改作更短的占位注释。
  - 删除 `<script>` 注释中重复的、不参与渲染的 "usage examples" 行（例如文件中段关于 React Hooks 的多行示例注释）。
- **严禁**删除：`MineradioDS` bundle 的实际可执行语句、`Component extends DCLogic` 类体、样式 `<style>` 块。

### NFR-2 preconnect / preload 补齐
- `<head>` 内（可在 helmet 段后或 line 232-233 同位置）补充：
  - `<link rel="preconnect" href="https://unpkg.com" crossorigin>`
  - `<link rel="preconnect" href="https://hm.baidu.com">`
  - `<link rel="preconnect" href="https://www.clarity.ms" crossorigin>`
  - `<link rel="preconnect" href="https://static.cloudflareinsights.com" crossorigin>`
  - `<link rel="preload" as="script" href="https://unpkg.com/react@18.3.1/umd/react.production.min.js" crossorigin>`
  - `<link rel="preload" as="script" href="https://unpkg.com/react-dom@18.3.1/umd/react-dom.production.min.js" crossorigin>`

### NFR-3 静态托管压缩 / 缓存提示配置
- 新建 `_headers` 文件（Cloudflare Pages / Netlify 兼容）：
  - 为 `.html`、`.js`、`.css`、字体、图片设置正确的 `Content-Encoding` 提示（启用自动压缩），以及 Cache-Control 策略（`index.html` = no-cache，静态资源 = 1y immutable）。
- 新建 `static.json` （可选，为 Vercel 风格宿主补充）：开启 brotli / gzip。

### NFR-4 改动不引入新的 console error
- 所有改动通过 agent-browser 执行 `errors` 命令时，返回 0 条 error 级日志。

## Constraints
- **Technical**: 必须在 `/workspace/index.html` 单文件 + 少量附属配置文件内完成；不能引入 Node 构建流水线。
- **Business**: 所有新增 CTA 链接指向官方 GitHub 仓库 Releases 页；不指向任何第三方镜像。
- **Dependencies**: 依赖 Cloudflare Pages 对 `_headers` 规则的支持；若部署者使用其它宿主，需手动等价迁移。

## Assumptions
- 部署平台支持标准 HTTP Response Headers（Cloudflare Pages 默认就支持 Brotli；`_headers` 用来加 Cache-Control）。
- `MineradioDS` 压缩 bundle 是可直接编辑的文本（实际是 IIFE），删除 bundle 顶部的 1 行 `/* @ds-bundle: ... */` 大 JSON 注释即可节省约 4-5KB，且运行时不被 JS 引擎执行。
- 评价跑马灯的 aria-hidden 副本与首 7 张卡片内容逐字一致，可复用同一份 `data-i18n` key。

## Acceptance Criteria

### AC-1 更新日志按钮点击能打开 Modal，并新增 GitHub Releases CTA
- **Type**: `rule`
- **Given**: 访问首页，且控制台无 error
- **When**: 点击 Footer「更新日志」/ Changelog 按钮
- **Then**: Modal 出现，其中有跳转到 `https://github.com/XxHuberrr/Mineradio/releases` 的 `<a target="_blank">` 链接
- **Pass Condition**: 元素存在且 `href` 完全匹配
- **Evidence**: agent-browser click + 截图 + 控制台 `errors` 0 条

### AC-2 英文模式下评价区 0 处中文文本
- **Type**: `rule`
- **Given**: 首页加载完成，lang=zh
- **When**: 点击 EN 按钮切到英文并等待 applyLang 执行完成
- **Then**: 在 `#praise` 范围内使用中文正则 `[\u4e00-\u9fff]` 搜索文本节点，结果数量 = 0
- **Pass Condition**: `count === 0`
- **Evidence**: agent-browser eval 返回计数

### AC-3 中文 hash `#功能` 自动映射到 `#features` 并滚动到位
- **Type**: `rule`
- **Given**: 浏览器尚未打开 mineradio.cn
- **When**: 直接访问 `index.html#功能`（hash 被 encode 为 `#%E5%8A%9F%E8%83%BD`）
- **Then**: (a) URL hash 最终为 `#features`；(b) `getBoundingClientRect().top` 对应 section 顶部 ≤ 100px
- **Pass Condition**: (a) && (b) 同时满足
- **Evidence**: agent-browser `get url` + eval

### AC-4 控制台无 `{{ x }} never resolved` warning
- **Type**: `rule`
- **Given**: 清空缓存刷新首页
- **When**: 等待 load 事件触发
- **Then**: 控制台所有 log/warn/error 级条目，不包含子串 `{{ x }} never resolved`
- **Pass Condition**: 0 次匹配
- **Evidence**: agent-browser `console` 命令输出 grep

### AC-5 HTML 体积瘦身 ≥ 10%
- **Type**: `rule`
- **Given**: 基线 `wc -c index.html` = 1,754,401
- **When**: 所有改动完成
- **Then**: `wc -c index.html` ≤ 1,578,961
- **Pass Condition**: 数值满足
- **Evidence**: shell `wc -c` 输出

### AC-6 preconnect / preload 6 条新增 link 全部存在于 head
- **Type**: `rule`
- **Given**: 首页 `<head>`
- **When**: 解析出所有 `<link rel>`
- **Then**: 存在 6 条与 NFR-2 精确匹配的条目（rel+href+crossorigin 一致）
- **Pass Condition**: 6/6 命中
- **Evidence**: agent-browser eval + DOM 检查

### AC-7 `_headers` 文件存在且包含 Brotli / Cache-Control 段
- **Type**: `rule`
- **Given**: `/workspace/` 根目录
- **When**: `ls` + `grep "_headers"`
- **Then**: 文件存在，并包含 `Content-Encoding: auto`（或说明段落）、以及对 `/index.html` 的 `Cache-Control: no-cache` 与对 `/*.js` / `/*.woff2` 的 `Cache-Control: public, max-age=31536000, immutable`
- **Pass Condition**: 文件存在 + 3 条规则 grep 命中
- **Evidence**: `cat _headers` 输出

### AC-8 改动后首页所有主要锚点跳转仍回归正常
- **Type**: `rule`
- **Given**: 首页加载完成
- **When**: 依次点击 Header 的 功能 / 下载 / 评价 / GitHub
- **Then**: 前三者滚动到对应区块并更新 hash，GitHub 外链正确
- **Pass Condition**: 4 项行为正确
- **Evidence**: agent-browser click + URL 检查

## Open Questions
- [ ] ~~部署平台是 Cloudflare Pages 还是 GitHub Pages / Netlify？~~ → 工作区有 `CNAME` 和 `.nojekyll`，推测 GitHub Pages。因此 `_headers` 在 GH Pages 上**不会生效**，但可以作为可迁移资产保留。
- [ ] ~~MineradioDS bundle 注释是否可编辑？~~ → 是的，`/* */` 注释在 JS 中不影响执行，删除安全。
