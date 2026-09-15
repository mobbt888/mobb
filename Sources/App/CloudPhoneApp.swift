import SwiftUI

@main
struct CloudPhoneApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var model = WebViewModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(model)
        }
        .onChange(of: scenePhase) { phase in
            guard phase == .active else { return }
            Task { await model.reloadIfStale() }
        }
    }
}
