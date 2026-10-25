import SwiftUI

@main
struct CurfewApp: App {
    @Environment(\.scenePhase) private var scenePhase

    init() {
        if SelfTest.isRequested {
            Demo.prepareIfRequested()
            SelfTest.run()
        }
        // Started here (not when a screen appears) so a background wake-up by Bluetooth is handled.
        _ = AppModel.shared
    }

    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active: AppModel.shared.appBecameActive()
            case .background: AppModel.shared.appWentToBackground()
            default: break
            }
        }
    }
}

struct RootView: View {
    @State private var model = AppModel.shared

    var body: some View {
        Group {
            if model.hasFinishedSetup {
                HomeView()
            } else {
                WelcomeView()
            }
        }
        .environment(model)
        .tint(Theme.accent)
    }
}
