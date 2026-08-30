import UIKit
import WebKit

/// Main browser screen — a 1:1 port of Android `MainActivity.kt`:
/// multi-tab WKWebView browser with a collapsible chrome bar, quick-login
/// chips, Bridge status, and a hidden Bridge host WebView that proxies
/// music API calls through the shared `chrome.*` polyfill.
final class BrowserViewController: UIViewController {

    // MARK: Views
    private let rootStack = UIStackView()
    private let chromeBar = UIView()
    private let toolbarRow = UIStackView()
    private let tabScroller = UIScrollView()
    private let tabStrip = UIStackView()
    private let urlBar = UITextField()
    private let chipsRow = UIStackView()
    private let bridgeStatus = UILabel()
    private let loadProgress = UIProgressView()
    private let webContainer = UIView()
    private let edgePeek = UIView()
    private let btnShowChrome = UIButton(type: .system)
    private var bridgeWebView: WKWebView!

    // MARK: State
    private var tabs: [String: BrowserTab] = [:]
    private var tabOrder: [String] = []
    private var activeTabId: String?
    private var pendingApi: [String: WKWebView] = [:]   // requestId -> originating page WebView
    private var bridgeReady = false
    private var bridgeVersion = MR.bridgeVersion
    private var chromeVisible = true
    private var pollAttempt = 0

    // KVO
    private var titleObs: NSKeyValueObservation?
    private var progressObs: NSKeyValueObservation?

    // Message handler proxies (break retain cycle with userContentController)
    private let pageProxy = MessageProxy()
    private let hostProxy = MessageProxy()

    // MARK: Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = MR.bg
        pageProxy.target = self; pageProxy.name = "MineradioAndroid"
        hostProxy.target = self; hostProxy.name = "MineradioHost"
        chromeVisible = UserDefaults.standard.bool(forKey: MR.chromeVisibleKey)
        // default true on first launch
        if !UserDefaults.standard.object(forKey: MR.chromeVisibleKey) is Bool {
            chromeVisible = true
        }
        setupUI()
        setupBridgeWebView()
        MR.dataStore.httpCookieStore.add(self)  // observe cookie changes
        openTab(MR.homeURL.absoluteString, activate: true)
    }

    // MARK: UI setup

    private func setupUI() {
        let safe = view.safeAreaLayoutGuide

        // Chrome bar
        chromeBar.backgroundColor = MR.bgElevated
        chromeBar.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(chromeBar)

        // Top toolbar row: back | forward | reload | home | tabs | new | hide
        let back = makeToolButton("chevron.backward", "后退")
        let fwd = makeToolButton("chevron.forward", "前进")
        let reload = makeToolButton("arrow.clockwise", "刷新")
        let home = makeToolButton("house", "主页")
        let newTab = makeToolButton("plus", "新标签")
        let hide = makeToolButton("chevron.up", "隐藏顶栏")

        tabScroller.showsHorizontalScrollIndicator = false
        tabScroller.translatesAutoresizingMaskIntoConstraints = false
        tabStrip.axis = .horizontal
        tabStrip.alignment = .center
        tabStrip.spacing = 6
        tabStrip.translatesAutoresizingMaskIntoConstraints = false
        tabScroller.addSubview(tabStrip)

        toolbarRow.axis = .horizontal
        toolbarRow.alignment = .center
        toolbarRow.spacing = 2
        toolbarRow.translatesAutoresizingMaskIntoConstraints = false
        [back, fwd, reload, home, tabScroller, newTab, hide].forEach { toolbarRow.addArrangedSubview($0) }

        // URL row
        urlBar.placeholder = "搜索或输入网址"
        urlBar.font = .systemFont(ofSize: 13)
        urlBar.textColor = MR.text
        urlBar.backgroundColor = MR.bg
        urlBar.layer.cornerRadius = 16
        urlBar.leftView = UIView(frame: CGRect(x: 0, y: 0, width: 14, height: 0))
        urlBar.leftViewMode = .always
        urlBar.rightView = UIView(frame: CGRect(x: 0, y: 0, width: 14, height: 0))
        urlBar.rightViewMode = .always
        urlBar.autocapitalizationType = .none
        urlBar.autocorrectionType = .no
        urlBar.keyboardType = .webSearch
        urlBar.returnKeyType = .go
        urlBar.borderStyle = .none
        urlBar.translatesAutoresizingMaskIntoConstraints = false
        urlBar.delegate = self
        urlBar.heightAnchor.constraint(equalToConstant: 32).isActive = true
        urlBar.setContentHuggingPriority(.defaultLow, for: .horizontal)
        urlBar.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let ne = makeChip("网易")
        let qq = makeChip("QQ")
        kg = makeChip("酷狗")
        bridgeStatus.font = .systemFont(ofSize: 11)
        bridgeStatus.textColor = MR.textDim
        bridgeStatus.text = "Bridge…"
        bridgeStatus.backgroundColor = MR.bg
        bridgeStatus.layer.cornerRadius = 12
        bridgeStatus.layer.masksToBounds = true
        bridgeStatus.textAlignment = .center
        bridgeStatus.heightAnchor.constraint(equalToConstant: 30).isActive = true
        bridgeStatus.widthAnchor.constraint(greaterThanOrEqualToConstant: 60).isActive = true
        let statusTap = UITapGestureRecognizer(target: self, action: #selector(retryBridge))
        bridgeStatus.addGestureRecognizer(statusTap)
        bridgeStatus.isUserInteractionEnabled = true

        chipsRow.axis = .horizontal
        chipsRow.alignment = .center
        chipsRow.spacing = 6
        chipsRow.distribution = .fill
        chipsRow.translatesAutoresizingMaskIntoConstraints = false
        [urlBar, ne, qq, kg!, bridgeStatus].forEach { chipsRow.addArrangedSubview($0) }

        // tabScroller expands to fill remaining toolbar width (stack-managed).
        tabScroller.setContentHuggingPriority(.defaultLow, for: .horizontal)
        tabScroller.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        loadProgress.progressTintColor = MR.accent
        loadProgress.trackTintColor = .clear
        loadProgress.translatesAutoresizingMaskIntoConstraints = false
        loadProgress.heightAnchor.constraint(equalToConstant: 2).isActive = true

        let chromeStack = UIStackView(arrangedSubviews: [toolbarRow, chipsRow, loadProgress])
        chromeStack.axis = .vertical
        chromeStack.spacing = 6
        chromeStack.translatesAutoresizingMaskIntoConstraints = false
        chromeStack.isLayoutMarginsRelativeArrangement = true
        chromeStack.directionalLayoutMargins = NSDirectionalEdgeInsets(top: 4, leading: 6, bottom: 2, trailing: 6)
        chromeBar.addSubview(chromeStack)

        // Web container
        webContainer.backgroundColor = MR.bg
        webContainer.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(webContainer)

        // Edge peek + show-chrome (overlay when hidden)
        edgePeek.backgroundColor = .clear
        edgePeek.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(edgePeek)
        let peekPan = UIPanGestureRecognizer(target: self, action: #selector(edgePeekPanned(_:)))
        edgePeek.addGestureRecognizer(peekPan)
        let peekTap = UITapGestureRecognizer(target: self, action: #selector(showChrome))
        edgePeek.addGestureRecognizer(peekTap)

        btnShowChrome.setTitle("显示顶栏", for: .normal)
        btnShowChrome.titleLabel?.font = .systemFont(ofSize: 12)
        btnShowChrome.setTitleColor(MR.accent, for: .normal)
        btnShowChrome.backgroundColor = MR.bgElevated
        btnShowChrome.layer.cornerRadius = 12
        btnShowChrome.translatesAutoresizingMaskIntoConstraints = false
        btnShowChrome.addTarget(self, action: #selector(showChrome), for: .touchUpInside)
        view.addSubview(btnShowChrome)

        // Bridge WebView (hidden, 1x1) is added in setupBridgeWebView().

        // Layout
        NSLayoutConstraint.activate([
            chromeBar.topAnchor.constraint(equalTo: safe.topAnchor),
            chromeBar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            chromeBar.trailingAnchor.constraint(equalTo: view.trailingAnchor),

            chromeStack.topAnchor.constraint(equalTo: chromeBar.topAnchor, constant: 4),
            chromeStack.leadingAnchor.constraint(equalTo: chromeBar.leadingAnchor, constant: 6),
            chromeStack.trailingAnchor.constraint(equalTo: chromeBar.trailingAnchor, constant: -6),
            chromeStack.bottomAnchor.constraint(equalTo: chromeBar.bottomAnchor, constant: -2),

            toolbarRow.heightAnchor.constraint(equalToConstant: 44),

            tabScroller.heightAnchor.constraint(equalTo: toolbarRow.heightAnchor),
            tabStrip.topAnchor.constraint(equalTo: tabScroller.topAnchor),
            tabStrip.bottomAnchor.constraint(equalTo: tabScroller.bottomAnchor),
            tabStrip.leadingAnchor.constraint(equalTo: tabScroller.leadingAnchor),
            tabStrip.trailingAnchor.constraint(equalTo: tabScroller.trailingAnchor),
            tabStrip.heightAnchor.constraint(equalTo: tabScroller.heightAnchor),

            webContainer.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            webContainer.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            webContainer.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            edgePeek.topAnchor.constraint(equalTo: view.topAnchor),
            edgePeek.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            edgePeek.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            edgePeek.heightAnchor.constraint(equalToConstant: 24),

            btnShowChrome.topAnchor.constraint(equalTo: safe.topAnchor, constant: 8),
            btnShowChrome.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            btnShowChrome.heightAnchor.constraint(equalToConstant: 32),
        ])

        // webContainer top toggles with chrome visibility
        webTopToChrome = webContainer.topAnchor.constraint(equalTo: chromeBar.bottomAnchor)
        webTopToTop = webContainer.topAnchor.constraint(equalTo: view.topAnchor)
        applyChromeVisibility(animated: false)

        // Toolbar actions
        back.addTarget(self, action: #selector(goBack), for: .touchUpInside)
        fwd.addTarget(self, action: #selector(goForward), for: .touchUpInside)
        reload.addTarget(self, action: #selector(reload), for: .touchUpInside)
        home.addTarget(self, action: #selector(goHome), for: .touchUpInside)
        newTab.addTarget(self, action: #selector(newTabTapped), for: .touchUpInside)
        hide.addTarget(self, action: #selector(hideChrome), for: .touchUpInside)
        ne.addTarget(self, action: #selector(openNE), for: .touchUpInside)
        qq.addTarget(self, action: #selector(openQQ), for: .touchUpInside)
        kg!.addTarget(self, action: #selector(openKG), for: .touchUpInside)
    }

    private var webTopToChrome: NSLayoutConstraint!
    private var webTopToTop: NSLayoutConstraint!
    private weak var kg: UIButton?

    private func makeToolButton(_ systemName: String, _ acc: String) -> UIButton {
        let b = UIButton(type: .system)
        b.setImage(UIImage(systemName: systemName), for: .normal)
        b.tintColor = MR.text
        b.widthAnchor.constraint(equalToConstant: 36).isActive = true
        b.heightAnchor.constraint(equalToConstant: 36).isActive = true
        b.accessibilityLabel = acc
        return b
    }

    private func makeChip(_ title: String) -> UIButton {
        let b = UIButton(type: .system)
        b.setTitle(title, for: .normal)
        b.titleLabel?.font = .systemFont(ofSize: 12, weight: .bold)
        b.setTitleColor(MR.accent, for: .normal)
        b.backgroundColor = MR.bg
        b.layer.cornerRadius = 12
        b.contentEdgeInsets = UIEdgeInsets(top: 6, left: 12, bottom: 6, right: 12)
        b.heightAnchor.constraint(equalToConstant: 30).isActive = true
        return b
    }

    // MARK: Chrome visibility

    @objc private func hideChrome() { setChromeVisible(false) }
    @objc private func showChrome() { setChromeVisible(true) }

    private func setChromeVisible(_ visible: Bool) {
        chromeVisible = visible
        UserDefaults.standard.set(visible, forKey: MR.chromeVisibleKey)
        applyChromeVisibility(animated: true)
    }

    private func applyChromeVisibility(animated: Bool) {
        webTopToTop.isActive = !chromeVisible
        webTopToChrome.isActive = chromeVisible
        chromeBar.isHidden = !chromeVisible
        edgePeek.isHidden = chromeVisible
        btnShowChrome.isHidden = chromeVisible
        if animated {
            btnShowChrome.alpha = chromeVisible ? 0 : 1
            UIView.animate(withDuration: 0.18) {
                self.view.layoutIfNeeded()
                self.chromeBar.alpha = self.chromeVisible ? 1 : 0
                self.btnShowChrome.alpha = self.chromeVisible ? 0 : 1
            }
        } else {
            chromeBar.alpha = chromeVisible ? 1 : 0
            btnShowChrome.alpha = chromeVisible ? 0 : 1
            view.layoutIfNeeded()
        }
    }

    @objc private func edgePeekPanned(_ pan: UIPanGestureRecognizer) {
        if pan.state == .ended || pan.state == .cancelled {
            let v = pan.velocity(in: view)
            if v.y > 300 { showChrome() }
        }
    }

    // MARK: Loading + navigation bar

    private func setLoading(_ loading: Bool, progress: Float = 0) {
        if loading {
            loadProgress.isHidden = false
            if progress > 0 && progress < 1 {
                loadProgress.progress = progress
            } else {
                loadProgress.setProgress(0.1, animated: true)
            }
        } else {
            loadProgress.isHidden = true
            loadProgress.setProgress(0, animated: false)
        }
    }

    private func navigateFromBar() {
        guard var raw = urlBar.text?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else { return }
        urlBar.resignFirstResponder()
        if !raw.contains("://") {
            if raw.contains(".") && !raw.contains(" ") {
                raw = "https://\(raw)"
            } else {
                let encoded = raw.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? raw
                raw = "https://www.bing.com/search?q=\(encoded)"
            }
        }
        activeWebView()?.load(URLRequest(url: URL(string: raw)!))
    }

    @objc private func goBack() { activeWebView()?.goBack() }
    @objc private func goForward() { activeWebView()?.goForward() }
    @objc private func reload() { activeWebView()?.reload() }
    @objc private func goHome() { activeWebView()?.load(URLRequest(url: MR.homeURL)) }
    @objc private func newTabTapped() { openTab(MR.homeURL.absoluteString, activate: true) }
    @objc private func openNE() { openTab("https://music.163.com/", activate: true) }
    @objc private func openQQ() { openTab("https://y.qq.com/", activate: true) }
    @objc private func openKG() { openTab("https://www.kugou.com/", activate: true) }

    // MARK: Tab management

    private func makePageConfig() -> WKWebViewConfiguration {
        let config = WKWebViewConfiguration()
        config.processPool = MR.processPool
        config.websiteDataStore = MR.dataStore
        config.preferences.javaScriptCanOpenWindowsAutomatically = true
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []
        let userCC = config.userContentController
        userCC.add(pageProxy, name: "MineradioAndroid")
        return config
    }

    private func openTab(_ url: String, activate: Bool) {
        let id = UUID().uuidString
        let webView = WKWebView(frame: .zero, configuration: makePageConfig())
        webView.translatesAutoresizingMaskIntoConstraints = false
        webView.customUserAgent = MR.desktopUA
        webView.allowsBackForwardNavigationGestures = true
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.backgroundColor = MR.bg
        webContainer.addSubview(webView)
        NSLayoutConstraint.activate([
            webView.topAnchor.constraint(equalTo: webContainer.topAnchor),
            webView.bottomAnchor.constraint(equalTo: webContainer.bottomAnchor),
            webView.leadingAnchor.constraint(equalTo: webContainer.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: webContainer.trailingAnchor),
        ])

        let (stripView, title, favicon, close) = BrowserTab.makeStripView()
        stripView.translatesAutoresizingMaskIntoConstraints = false
        stripView.heightAnchor.constraint(equalToConstant: 30).isActive = true
        tabStrip.addArrangedSubview(stripView)
        let tap = UITapGestureRecognizer(target: self, action: #selector(tabTapped(_:)))
        stripView.addGestureRecognizer(tap)
        let longPress = UILongGestureRecognizer(target: self, action: #selector(tabLongPressed(_:)))
        stripView.addGestureRecognizer(longPress)
        close.addTarget(self, action: #selector(tabCloseTapped(_:)))
        // Gesture `.view` is read-only (auto-bound to the attached view).

        let tab = BrowserTab(id: id, webView: webView, stripView: stripView,
                            titleLabel: title, faviconView: favicon, closeButton: close, url: url)
        tabs[id] = tab
        tabOrder.append(id)
        setCloseTag(for: tab)
        webView.load(URLRequest(url: URL(string: url)!))
        if activate { activateTab(id) } else { webView.isHidden = true }
    }

    private var closeTagSeed = 0
    private var tabByCloseTag: [Int: String] = [:]
    private func setCloseTag(for tab: BrowserTab) {
        closeTagSeed += 1
        tab.closeButton.tag = closeTagSeed
        tabByCloseTag[closeTagSeed] = tab.id
    }

    @objc private func tabTapped(_ g: UITapGestureRecognizer) {
        guard let strip = g.view, let id = tabId(forStrip: strip) else { return }
        activateTab(id)
    }

    @objc private func tabLongPressed(_ g: UILongGestureRecognizer) {
        guard g.state == .began, let strip = g.view, let id = tabId(forStrip: strip) else { return }
        closeTab(id)
    }

    @objc private func tabCloseTapped(_ b: UIButton) {
        guard let id = tabByCloseTag[b.tag] else { return }
        closeTab(id)
    }

    private func tabId(forStrip strip: UIView) -> String? {
        for tab in tabs.values where tab.stripView === strip { return tab.id }
        return nil
    }

    private func activateTab(_ id: String) {
        activeTabId = id
        for (tabId, tab) in tabs {
            let active = tabId == id
            tab.webView.isHidden = !active
            tab.stripView.backgroundColor = active ? MR.bgElevated : MR.bg
            tab.stripView.layer.borderColor = (active ? MR.accent : MR.border).cgColor
            tab.titleLabel.textColor = active ? MR.text : MR.textDim
            if active {
                urlBar.text = tab.webView.url?.absoluteString ?? tab.url
                setLoading(tab.webView.estimatedProgress > 0 && tab.webView.estimatedProgress < 1,
                          progress: Float(tab.webView.estimatedProgress))
                attachObservers(tab: tab)
            }
        }
        // scroll active tab into view
        if let tab = tabs[id] {
            stripScroll(to: tab)
        }
    }

    private func stripScroll(to tab: BrowserTab) {
        DispatchQueue.main.async {
            let frame = tab.stripView.frame
            if frame.width > 0 {
                let target = max(0, frame.origin.x - 24)
                self.tabScroller.setContentOffset(CGPoint(x: target, y: 0), animated: true)
            }
        }
    }

    private func closeTab(_ id: String) {
        guard let tab = tabs.removeValue(forKey: id) else { return }
        tabOrder.removeAll { $0 == id }
        if activeTabId == id { titleObs = nil; progressObs = nil }
        tab.webView.removeFromSuperview()
        tabStrip.removeArrangedSubview(tab.stripView)
        tab.stripView.removeFromSuperview()
        if tabs.isEmpty {
            openTab(MR.homeURL.absoluteString, activate: true)
            return
        }
        if activeTabId == id, let next = tabOrder.last { activateTab(next) }
    }

    private func activeWebView() -> WKWebView? {
        guard let id = activeTabId else { return nil }
        return tabs[id]?.webView
    }

    // MARK: KVO for title/progress

    private func attachObservers(tab: BrowserTab) {
        titleObs = nil
        progressObs = nil
        let wv = tab.webView
        titleObs = wv.observe(\.title, options: [.new]) { [weak self] w, _ in
            guard let self = self, w === self.activeWebView() else { return }
            let title = w.title?.trimmingCharacters(in: .whitespacesAndNewlines)
            DispatchQueue.main.async {
                tab.titleLabel.text = (title?.isEmpty == false ? title! : tab.url).prefix(18).description
                self.setFavicon(for: tab)
            }
        }
        progressObs = wv.observe(\.estimatedProgress, options: [.new]) { [weak self] w, _ in
            guard let self = self, w === self.activeWebView() else { return }
            DispatchQueue.main.async {
                let p = Float(w.estimatedProgress)
                if p > 0 && p < 1 { self.setLoading(true, progress: p) }
                else if p >= 1 { self.setLoading(false) }
            }
        }
    }

    private func setFavicon(for tab: BrowserTab) {
        guard let host = URL(string: tab.url)?.host, !host.isEmpty else {
            tab.faviconView.isHidden = true
            return
        }
        tab.faviconView.isHidden = false
        let fav = URL(string: "https://www.google.com/s2/favicons?sz=64&domain=\(host)")
        if let fav = fav {
            DispatchQueue.global().async {
                if let data = try? Data(contentsOf: fav), let img = UIImage(data: data) {
                    DispatchQueue.main.async { tab.faviconView.image = img }
                }
            }
        }
    }

    // MARK: Bridge host

    private func setupBridgeWebView() {
        let config = WKWebViewConfiguration()
        config.processPool = MR.processPool
        config.websiteDataStore = MR.dataStore
        config.preferences.javaScriptEnabled = true
        config.setURLSchemeHandler(BridgeSchemeHandler(), forURLScheme: MR.bridgeScheme)
        config.userContentController.add(hostProxy, name: "MineradioHost")
        let bridge = WKWebView(frame: .zero, configuration: config)
        bridge.translatesAutoresizingMaskIntoConstraints = false
        bridge.navigationDelegate = self
        view.addSubview(bridge)
        NSLayoutConstraint.activate([
            bridge.widthAnchor.constraint(equalToConstant: 1),
            bridge.heightAnchor.constraint(equalToConstant: 1),
            bridge.topAnchor.constraint(equalTo: view.topAnchor),
            bridge.leadingAnchor.constraint(equalTo: view.leadingAnchor),
        ])
        self.bridgeWebView = bridge
        let url = URL(string: "\(MR.bridgeScheme)://app/host/runner.html")!
        bridge.load(URLRequest(url: url))
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
            self?.pollBridgeReady(0)
        }
    }

    private func bridge() -> WKWebView? { bridgeWebView }

    private func pollBridgeReady(_ attempt: Int) {
        guard let b = bridge() else { return }
        if bridgeReady || attempt > 20 { updateBridgeStatus(); return }
        b.evaluateJavaScript(
            "(function(){return window.__mineradioBridgeHostReady ? (window.__bridgeVersion||'\(MR.bridgeVersion)') : '';})()"
        ) { [weak self] value, _ in
            guard let self = self else { return }
            let ver = (value as? String)?.trimmingCharacters(in: CharacterSet(charactersIn: "\""))
                .flatMap { $0.isEmpty ? nil : $0 }
            if let ver = ver, ver != "null" {
                let wasReady = self.bridgeReady
                self.bridgeVersion = ver
                self.bridgeReady = true
                self.updateBridgeStatus()
                self.syncCookiesToBridge()
                self.syncStorageToBridge()
                if !wasReady { self.reinjectBridgeAllTabs() }
            } else {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                    self.pollBridgeReady(attempt + 1)
                }
            }
        }
    }

    private func updateBridgeStatus() {
        DispatchQueue.main.async {
            if self.bridgeReady {
                self.bridgeStatus.text = "Bridge \(self.bridgeVersion)"
                self.bridgeStatus.textColor = MR.accent
                self.bridgeStatus.isUserInteractionEnabled = false
            } else {
                self.bridgeStatus.text = "Bridge 未就绪 · 点击重试"
                self.bridgeStatus.textColor = MR.danger
                self.bridgeStatus.isUserInteractionEnabled = true
            }
        }
    }

    @objc private func retryBridge() {
        guard !bridgeReady, let b = bridge() else { return }
        bridgeStatus.text = "Bridge 重试中…"
        b.reload()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
            self?.pollBridgeReady(0)
        }
    }

    private func reinjectBridgeAllTabs() {
        for tab in tabs.values {
            let url = tab.webView.url?.absoluteString ?? tab.url
            if isMineradioUrl(url) { injectBridge(into: tab.webView) }
        }
    }

    // MARK: Bridge injection into mineradio pages

    private func injectBridge(into webView: WKWebView) {
        let boot = """
        (function(){
          if (!window.mineradioDesktop) {
            window.__mrPending = window.__mrPending || {};
            window.mineradioDesktop = {
              version: \(NativeHttp.quote(MR.bridgeVersion)),
              extId: 'mineradio-ios',
              invokeApi: function(payload){
                return new Promise(function(resolve, reject){
                  var id = 'r' + Date.now() + '_' + Math.random().toString(16).slice(2);
                  window.__mrPending[id] = { resolve: resolve, reject: reject };
                  try { window.webkit.messageHandlers.MineradioAndroid.postMessage({ id: id, payload: payload || {} }); }
                  catch (e) { delete window.__mrPending[id]; reject(e); }
                });
              },
              ensureMediaRules: function(){}
            };
            window.__mineradioApiResult = function(id, raw){
              var pending = window.__mrPending && window.__mrPending[id];
              if (!pending) return;
              delete window.__mrPending[id];
              try { var obj = (typeof raw === 'string') ? JSON.parse(raw) : raw; pending.resolve(obj); }
              catch (err) { pending.reject(err); }
            };
          }
        })();
        """
        webView.evaluateJavaScript(boot) { [weak self] _, _ in
            guard let self = self,
                  let url = Bundle.main.url(forResource: "inject", withExtension: "js", subdirectory: "Resources/host")
                    ?? Bundle.main.url(forResource: "inject", withExtension: "js", subdirectory: "host"),
                  let src = try? String(contentsOf: url, encoding: .utf8) else { return }
            webView.evaluateJavaScript(src)
        }
    }

    private func isMineradioUrl(_ urlStr: String) -> Bool {
        guard let u = URL(string: urlStr) else { return false }
        let host = (u.host ?? "").lowercased()
        if host == "mineradio.art" || host == "www.mineradio.art" ||
            host == "localhost" || host == "127.0.0.1" { return true }
        if host.contains("xxhuberrr.github.io") && u.path.hasPrefix("/Mineradio") { return true }
        return false
    }

    // MARK: Message handling

    func handleMessage(_ name: String, message: WKScriptMessage) {
        switch name {
        case "MineradioAndroid":
            handlePageInvoke(message)
        case "MineradioHost":
            handleHostMessage(message)
        default: break
        }
    }

    /// Page -> native: {id, payload}. Route into Bridge `__handleApi`, deliver
    /// result back to the originating page via `__mineradioApiResult`.
    private func handlePageInvoke(_ message: WKScriptMessage) {
        guard let pageWebView = message.webView,
              let body = message.body as? [String: Any],
              let id = body["id"] as? String else { return }
        let payload = body["payload"] ?? [:]
        guard bridgeReady, let b = bridge() else {
            deliverApiResult(pageWebView, requestId: id, resultJson: #"{"ok":false,"error":"Bridge host not ready"}"#)
            return
        }
        guard JSONSerialization.isValidJSONObject(payload),
              let data = try? JSONSerialization.data(withJSONObject: payload),
              let payloadStr = String(data: data, encoding: .utf8) else {
            deliverApiResult(pageWebView, requestId: id, resultJson: #"{"ok":false,"error":"invalid payload"}"#)
            return
        }
        pendingApi[id] = pageWebView
        let escaped = NativeHttp.quote(payloadStr)
        let idLit = NativeHttp.quote(id)
        let js = """
        (async function(){
          try {
            var payload = JSON.parse(\(escaped));
            var data = await window.__handleApi(payload);
            window.__mineradioPostApiResult(\(idLit), JSON.stringify({ok:true, data:data}));
          } catch (e) {
            window.__mineradioPostApiResult(\(idLit), JSON.stringify({ok:false, error: String(e && e.message || e)}));
          }
        })();
        """
        b.evaluateJavaScript(js)
    }

    /// Bridge host -> native: {op, ...}. Handles setCookie / storageSet /
    /// startHttp / apiResult.
    private func handleHostMessage(_ message: WKScriptMessage) {
        guard let body = message.body as? [String: Any], let op = body["op"] as? String else { return }
        switch op {
        case "setCookie":
            if let urlStr = body["url"] as? String, let cookie = body["cookie"] as? String {
                setCookieOnStore(url: urlStr, cookie: cookie)
            }
        case "storageSet":
            if let key = body["key"] as? String, let value = body["value"] as? String {
                UserDefaults.standard.set(value, forKey: key)
                var manifest = storageManifest
                if !manifest.contains(key) {
                    manifest.append(key)
                    UserDefaults.standard.set(manifest, forKey: "bridge_storage_manifest")
                }
            }
        case "startHttp":
            if let id = body["id"] as? String, let spec = body["spec"] as? String, let b = bridge() {
                NativeHttp.shared.start(requestId: id, specJson: spec, bridge: b) { _ in }
            }
        case "apiResult":
            if let id = body["id"] as? String, let json = body["json"] as? String {
                if let pageWebView = pendingApi.removeValue(forKey: id) {
                    deliverApiResult(pageWebView, requestId: id, resultJson: json)
                }
            }
        default: break
        }
    }

    private func deliverApiResult(_ webView: WKWebView, requestId: String, resultJson: String) {
        let idLit = NativeHttp.quote(requestId)
        let jsonLit = NativeHttp.quote(resultJson)
        webView.evaluateJavaScript("window.__mineradioApiResult && window.__mineradioApiResult(\(idLit), \(jsonLit));")
    }

    // MARK: Cookie / storage sync into Bridge

    private func setCookieOnStore(url: String, cookie: String) {
        guard let url = URL(string: url) else { return }
        let fields = ["Set-Cookie": cookie]
        for c in HTTPCookie.cookies(withResponseHeaderFields: fields, for: url) {
            MR.dataStore.httpCookieStore.setCookie(c)
        }
    }

    private func syncCookiesToBridge() {
        guard let b = bridge() else { return }
        MR.dataStore.httpCookieStore.getAllCookies { cookies in
            let arr: [[String: Any]] = cookies.map {
                ["name": $0.name, "value": $0.value, "domain": $0.domain,
                 "path": $0.path, "secure": $0.isSecure]
            }
            guard let data = try? JSONSerialization.data(withJSONObject: arr),
                  let str = String(data: data, encoding: .utf8) else { return }
            DispatchQueue.main.async {
                b.evaluateJavaScript("window.__mineradioCookieSync && window.__mineradioCookieSync(\(str));")
            }
        }
    }

    private func syncStorageToBridge() {
        guard let b = bridge() else { return }
        var dict: [String: String] = [:]
        for k in storageManifest { dict[k] = UserDefaults.standard.string(forKey: k) ?? "" }
        guard let data = try? JSONSerialization.data(withJSONObject: dict),
              let str = String(data: data, encoding: .utf8) else { return }
        b.evaluateJavaScript("window.__mineradioStorageSync && window.__mineradioStorageSync(\(str));")
    }

    private var storageManifest: [String] {
        (UserDefaults.standard.array(forKey: "bridge_storage_manifest") as? [String]) ?? []
    }
}

// MARK: - TextField

extension BrowserViewController: UITextFieldDelegate {
    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        navigateFromBar()
        return false
    }
    func textFieldDidBeginEditing(_ textField: UITextField) {
        textField.selectAll(nil)
    }
}

// MARK: - WKNavigationDelegate

extension BrowserViewController: WKNavigationDelegate {
    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        if let tab = tab(forWebView: webView), tab.id == activeTabId {
            if let url = webView.url { urlBar.text = url.absoluteString }
            setLoading(true)
        }
    }

    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        if let url = webView.url, isMineradioUrl(url.absoluteString) {
            injectBridge(into: webView)
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        if let tab = tab(forWebView: webView) {
            let urlStr = webView.url?.absoluteString ?? tab.url
            tab.url = urlStr
            if tab.id == activeTabId { urlBar.text = urlStr; setLoading(false) }
            if isMineradioUrl(urlStr) { injectBridge(into: webView) }
        }
    }

    private func tab(forWebView wv: WKWebView) -> BrowserTab? {
        for t in tabs.values where t.webView === wv { return t }
        return nil
    }
}

// MARK: - WKUIDelegate (window.open -> new tab)

extension BrowserViewController: WKUIDelegate {
    func webView(_ webView: WKWebView,
                 createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction,
                 windowFeatures: WKWindowFeatures) -> WKWebView {
        let popup = WKWebView(frame: .zero, configuration: configuration)
        popup.customUserAgent = MR.desktopUA
        popup.allowsBackForwardNavigationGestures = true
        popup.navigationDelegate = self
        popup.uiDelegate = self
        popup.backgroundColor = MR.bg
        popup.translatesAutoresizingMaskIntoConstraints = false
        webContainer.addSubview(popup)
        NSLayoutConstraint.activate([
            popup.topAnchor.constraint(equalTo: webContainer.topAnchor),
            popup.bottomAnchor.constraint(equalTo: webContainer.bottomAnchor),
            popup.leadingAnchor.constraint(equalTo: webContainer.leadingAnchor),
            popup.trailingAnchor.constraint(equalTo: webContainer.trailingAnchor),
        ])
        let id = UUID().uuidString
        let (stripView, title, favicon, close) = BrowserTab.makeStripView()
        stripView.translatesAutoresizingMaskIntoConstraints = false
        stripView.heightAnchor.constraint(equalToConstant: 30).isActive = true
        tabStrip.addArrangedSubview(stripView)
        let tab = BrowserTab(id: id, webView: popup, stripView: stripView,
                             titleLabel: title, faviconView: favicon, closeButton: close, url: "about:blank")
        tabs[id] = tab
        tabOrder.append(id)
        setCloseTag(for: tab)
        activateTab(id)
        return popup
    }
}

// MARK: - Cookie store observer

extension BrowserViewController: WKHTTPCookieStoreObserver {
    func cookiesDidChange(in cookieStore: WKHTTPCookieStore) {
        DispatchQueue.main.async { [weak self] in self?.syncCookiesToBridge() }
    }
}

// MARK: - Message proxy

private final class MessageProxy: NSObject, WKScriptMessageHandler {
    weak var target: BrowserViewController?
    var name: String = ""
    func userContentController(_ userContentController: WKUserContentController,
                               didReceive message: WKScriptMessage) {
        target?.handleMessage(name, message: message)
    }
}
