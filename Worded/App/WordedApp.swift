import SwiftUI

@main
struct WordedApp: App {
    @StateObject private var app: AppState

    init() {
        AppState.migrateLegacyDefaults()
        _app = StateObject(wrappedValue: AppState())
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(app)
                .preferredColorScheme(.light)
        }
    }
}

struct RootView: View {
    @EnvironmentObject var app: AppState
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Group {
            if app.isLoading {
                LaunchLoadingView()
            } else if app.session == nil {
                AuthView()
            } else if app.profile == nil {
                // Signed in (Apple/email) but hasn't picked a username yet.
                AuthView()
            } else {
                HomeView()
            }
        }
        .task { await app.bootstrap() }
        .onOpenURL { url in
            Task { await app.handleIncomingURL(url) }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                app.recordActivity()
                app.enforceSessionRetention()
                app.challengePolling(active: true)
            } else {
                app.challengePolling(active: false)
            }
        }
    }
}

struct LaunchLoadingView: View {
    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            VStack(spacing: 16) {
                Text("WORDED")
                    .font(.system(size: 40, weight: .black, design: .rounded))
                    .foregroundColor(Theme.tileFace)
                ProgressView()
                    .tint(.white)
            }
        }
    }
}
