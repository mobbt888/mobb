import Combine
import UIKit
import WebKit

/// WebView 错误包装，用于在 SwiftUI 里以 `.alert` / 覆盖层展示。
struct WebError: Identifiable {
    let id = UUID()
    let message: String
    let recoverySuggestion: String
}

/// 负责 WKWebView 的创建、导航策略、进度与错误状态。
///
/// 所有状态标注为 `@MainActor`，避免从 WebKit 回调跨线程更新 UI。
@MainActor
final class WebViewModel: NSObject, ObservableObject {

    @Published private(set) var progress: Double = 0
    @Published private(set) var isLoading = false
    @Published private(set) var canGoBack = false
    @Published private(set) var pageTitle: String = ""
    @Published var error: WebError?

    private weak var webView: WKWebView?
    private var cancellables = Set<AnyCancellable>()
    private var lastFinished = Date.distantPast

    /// 首屏是否真正渲染完成。
    ///
    /// 未完成前：1) 禁止任何「回前台刷新」逻辑介入（否则会打断冷启动中的首次导航 → 白屏）；
    /// 2) 界面显示转圈，而不是让用户对着白屏以为卡死。
    @Published private(set) var hasLoadedOnce = false
    /// 主文档是否已 commit（区别于「只是发起了导航」）。
    private var hasCommittedPage = false
    /// 首屏兜底重试次数。
    private var firstLoadRetries = 0
    /// 首屏看门狗：超时仍没渲染出来就自动重载。
    private var watchdog: DispatchWorkItem?

    // MARK: - 生命周期

    /// 创建统一管理持有的 WebView。整个生命周期只应调用一次。
    func makeWebView() -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.allowsInlineMediaPlayback = true          // 云手机画面多为内联视频流
        configuration.mediaTypesRequiringUserActionForPlayback = []
        configuration.applicationNameForUserAgent = AppConfig.applicationNameForUserAgent

        let preferences = WKWebpagePreferences()
        preferences.allowsContentJavaScript = true
        configuration.defaultWebpagePreferences = preferences

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.allowsBackForwardNavigationGestures = true
        webView.backgroundColor = .systemBackground
        webView.scrollView.backgroundColor = .systemBackground
        webView.scrollView.contentInsetAdjustmentBehavior = .always
        webView.scrollView.refreshControl = UIRefreshControl()
        webView.scrollView.refreshControl?.addTarget(self, action: #selector(handlePullToRefresh), for: .valueChanged)

        self.webView = webView
        bind(webView)
        scheduleInitialLoad(for: webView)

        return webView
    }

    /// 首次导航推迟到下一个 runloop：`makeUIView` 返回时 WebView 还没挂进 window，
    /// 冷启动（WebKit 内容进程尚未就绪）时立刻 load 偶发「导航被丢弃 → 一直白屏」。
    ///
    /// 按 webView 实例判断而非一次性标志：SwiftUI 重复调用 `makeUIView` 时，
    /// 旧实例作废、新实例必须照常发起加载，否则会永久白屏。
    private func scheduleInitialLoad(for webView: WKWebView) {
        DispatchQueue.main.async { [weak self, weak webView] in
            guard let self, let webView, self.webView === webView, webView.url == nil else { return }
            self.loadRoot()
        }
    }

    func loadRoot() {
        guard let webView else { return }
        error = nil
        armWatchdog()
        webView.load(URLRequest(url: AppConfig.rootURL))
    }

    func reload() {
        error = nil
        if !hasLoadedOnce { armWatchdog() }
        guard let webView else { return }
        if hasCommittedPage || webView.url != nil {
            webView.reload()
        } else {
            // 还没有已提交的文档时 `reload()` 是空操作（首屏被丢弃的情形），必须重新发请求。
            loadRoot()
        }
    }

    func goBack() {
        webView?.goBack()
    }

    /// 长时间回到后台后再进前台，页面会话大概率已失效，重新拉取。
    ///
    /// 🔴 首屏没渲染完（`hasLoadedOnce == false`）或正在加载时一律不介入：
    /// 冷启动瞬间 `scenePhase` 就会变成 `.active`，此时 `lastFinished` 还是 `distantPast`，
    /// 一旦 reload 就会打断首次导航 —— 这正是「第一次打开白屏、退出重进才正常」的成因。
    func reloadIfStale() async {
        guard hasLoadedOnce, let webView, !webView.isLoading else { return }
        guard Date().timeIntervalSince(lastFinished) > AppConfig.staleInterval else { return }
        reload()
    }

    /// 看门狗：冷启动时 WebKit 内容进程异常（导航被取消 / 进程被回收）会表现为
    /// 一直白屏且没有任何回调 —— 超时未渲染成功就自动重来；连试几次仍不行则弹出
    /// 可见的错误层，至少让用户有「重试」可点，而不是对着白屏干等。
    private func armWatchdog() {
        watchdog?.cancel()
        guard firstLoadRetries <= AppConfig.maxFirstLoadRetries else { return }
        scheduleWatchdog()
    }

    private func scheduleWatchdog() {
        let item = DispatchWorkItem { [weak self] in
            guard let self, !self.hasLoadedOnce, let webView = self.webView else { return }

            // 有进度说明在正常加载（首屏体积大时可能超过看门狗时长），继续等，不计入重试。
            if webView.isLoading, webView.estimatedProgress >= 0.15 {
                self.scheduleWatchdog()
                return
            }

            self.firstLoadRetries += 1
            guard self.firstLoadRetries > AppConfig.maxFirstLoadRetries else {
                // 导航压根没 commit（被丢弃）时 reload 是空操作，必须重新发请求。
                if self.hasCommittedPage {
                    self.reload()
                } else {
                    self.loadRoot()
                }
                return
            }

            // 自动重试全部失败：给出可见提示，并重置计数，用户点「重试」可再来一轮。
            self.firstLoadRetries = 0
            self.error = WebError(
                message: "页面加载失败",
                recoverySuggestion: "网络较慢或站点暂时无响应，请点击重试。"
            )
        }
        watchdog = item
        DispatchQueue.main.asyncAfter(deadline: .now() + AppConfig.firstLoadTimeout, execute: item)
    }

    private func cancelWatchdog() {
        watchdog?.cancel()
        watchdog = nil
    }

    // MARK: - 内部

    private func bind(_ webView: WKWebView) {
        webView.publisher(for: \.estimatedProgress)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.progress = $0 }
            .store(in: &cancellables)

        webView.publisher(for: \.isLoading)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in
                self?.isLoading = $0
                if $0 { self?.error = nil }
            }
            .store(in: &cancellables)

        webView.publisher(for: \.canGoBack)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.canGoBack = $0 }
            .store(in: &cancellables)

        webView.publisher(for: \.title)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.pageTitle = $0 ?? "" }
            .store(in: &cancellables)
    }

    @objc private func handlePullToRefresh(_ sender: UIRefreshControl) {
        reload()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { sender.endRefreshing() }
    }

    private func handle(_ error: Error) {
        let nsError = error as NSError
        guard nsError.domain == NSURLErrorDomain, nsError.code == NSURLErrorCancelled else {
            cancelWatchdog()
            present(error)
            return
        }

        // 首屏加载途中被系统取消（切换前后台、重入等）：WebKit 既不报错也不重试，
        // 用户看到的就是一直白屏，这里补一次重试。
        guard !hasLoadedOnce, firstLoadRetries < AppConfig.maxFirstLoadRetries else { return }
        firstLoadRetries += 1
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
            guard let self, !self.hasLoadedOnce else { return }
            self.loadRoot()
        }
    }

    private func present(_ error: Error) {
        let nsError = error as NSError
        self.error = WebError(
            message: nsError.code == NSURLErrorNotConnectedToInternet ? "网络似乎断开了" : "页面加载失败",
            recoverySuggestion: nsError.code == NSURLErrorNotConnectedToInternet
                ? "请连接网络后下拉或点击重试。"
                : "请稍后再试，或下拉页面重新加载。"
        )
    }

    private func openExternally(_ url: URL) {
        guard UIApplication.shared.canOpenURL(url) else { return }
        UIApplication.shared.open(url, options: [:])
    }
}

// MARK: - WKNavigationDelegate

extension WebViewModel: WKNavigationDelegate {

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
    ) {
        guard let url = navigationAction.request.url else {
            decisionHandler(.cancel)
            return
        }
        guard AppConfig.isAllowed(url) else {
            if AppConfig.opensExternalInSafari { openExternally(url) }
            decisionHandler(.cancel)
            return
        }
        decisionHandler(.allow)
    }

    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        hasCommittedPage = true
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        lastFinished = Date()
        hasLoadedOnce = true
        hasCommittedPage = true
        firstLoadRetries = 0
        cancelWatchdog()
        error = nil
    }

    /// WebKit 内容进程被回收（内存压力 / 冷启动初始化失败）时，页面会直接变白
    /// 且不触发任何 didFail —— 必须在这里自愈，否则只能靠用户杀掉重进。
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        hasLoadedOnce = false
        hasCommittedPage = false
        firstLoadRetries = 0
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if webView.url == nil {
                self.loadRoot()
            } else {
                self.reload()
            }
        }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        handle(error)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        handle(error)
    }
}

// MARK: - WKUIDelegate

extension WebViewModel: WKUIDelegate {

    /// JS `window.open` / `target=_blank` 出来的页面交给系统浏览器，避免在壳内丢掉返回能力。
    func webView(
        _ webView: WKWebView,
        createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction,
        windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        if let url = navigationAction.request.url, AppConfig.opensExternalInSafari {
            openExternally(url)
        }
        return nil
    }
}
