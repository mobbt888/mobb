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
        loadRoot()

        return webView
    }

    func loadRoot() {
        error = nil
        _ = webView?.load(URLRequest(url: AppConfig.rootURL))
    }

    func reload() {
        error = nil
        webView?.reload()
    }

    func goBack() {
        webView?.goBack()
    }

    /// 长时间回到后台后再进前台，页面会话大概率已失效，重新拉取。
    func reloadIfStale() async {
        guard Date().timeIntervalSince(lastFinished) > AppConfig.staleInterval else { return }
        reload()
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
            present(error)
            return
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

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        lastFinished = Date()
        error = nil
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
