import SwiftUI
import WebKit

/// 把 `WebViewModel` 持有的 WKWebView 桥接到 SwiftUI。
struct RepresentedWebView: UIViewRepresentable {
    @EnvironmentObject private var model: WebViewModel

    func makeUIView(context: Context) -> WKWebView {
        model.makeWebView()
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {
        // 状态由 ViewModel 通过 Combine 驱动，这里无需同步。
    }
}
