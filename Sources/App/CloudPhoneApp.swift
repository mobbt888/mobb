import SwiftUI

@main
struct CloudPhoneApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var model = WebViewModel()
    @State private var showSplash = true

    var body: some Scene {
        WindowGroup {
            ZStack {
                RootView()
                    .environmentObject(model)
                if showSplash {
                    SplashView()
                        .transition(.opacity)
                }
            }
            // 开屏期间 WebView 照常加载，落下开幕就看到页面
            .task {
                try? await Task.sleep(nanoseconds: UInt64(AppConfig.splashDuration) * 1_000_000_000)
                withAnimation(.easeOut(duration: 0.35)) { showSplash = false }
            }
        }
        .onChange(of: scenePhase) { phase in
            guard phase == .active else { return }
            Task { await model.reloadIfStale() }
        }
    }
}
