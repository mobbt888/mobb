import SwiftUI

/// 主页：WebView + 加载进度 + 错误覆盖层 + 网页返回按钮。
struct RootView: View {
    @EnvironmentObject private var model: WebViewModel

    var body: some View {
        ZStack(alignment: .top) {
            RepresentedWebView()
                // WebView 自身按 `contentInsetAdjustmentBehavior = .always` 处理安全区，
                // 交由系统计算可避免 Home Indicator 处出现双重留白。
                .ignoresSafeArea(.container, edges: .bottom)

            ProgressBar(progress: model.progress, isVisible: model.isLoading)

            VStack {
                Spacer()
                HStack {
                    if model.canGoBack {
                        BackButton { model.goBack() }
                            .transition(.move(edge: .leading).combined(with: .opacity))
                    }
                    Spacer()
                }
                .padding(.leading, 16)
                .padding(.bottom, 24)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: model.canGoBack)
        .animation(.easeOut(duration: 0.2), value: model.isLoading)
        .overlay {
            if let error = model.error {
                ErrorOverlay(error: error) { model.reload() }
                    .background(Color(.systemBackground))
            } else if !model.hasLoadedOnce {
                // 首屏尚未渲染完成：给个转圈，避免用户对着白屏以为 App 卡死。
                // 🔴 冷启动白屏的观感问题主要来自这里 —— WebKit 首次内容进程初始化期间没有进度回调。
                ProgressView()
                    .controlSize(.large)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(.systemBackground))
                    .accessibilityLabel("正在加载")
            }
        }
    }
}

// MARK: - 子组件

private struct ProgressBar: View {
    let progress: Double
    let isVisible: Bool

    var body: some View {
        ProgressView(value: max(progress, isVisible ? 0.05 : 0), total: 1)
            .progressViewStyle(.linear)
            .tint(.accentColor)
            .opacity(isVisible ? 1 : 0)
            .animation(.easeOut(duration: 0.2), value: progress)
    }
}

private struct BackButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "chevron.left")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.primary)
                .frame(width: 44, height: 44)
                .background(.ultraThinMaterial, in: Circle())
        }
        .buttonStyle(.plain)
        .contentShape(Circle())
        .accessibilityLabel("返回上一页")
        .accessibilityHint("返回云手机站点的上一个页面")
    }
}

private struct ErrorOverlay: View {
    let error: WebError
    let retry: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "wifi.exclamationmark")
                .font(.system(size: 44))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)

            Text(error.message)
                .font(.headline)

            Text(error.recoverySuggestion)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Button("重试", action: retry)
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .padding(.top, 8)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    RootView()
        .environmentObject(WebViewModel())
}
