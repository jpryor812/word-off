import SwiftUI

@main
struct WordOffApp: App {
    @StateObject private var app = AppState()

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

    var body: some View {
        Group {
            if app.isLoading {
                LaunchLoadingView()
            } else if app.session == nil {
                AuthView()
            } else {
                HomeView()
            }
        }
        .task { await app.bootstrap() }
    }
}

struct LaunchLoadingView: View {
    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            VStack(spacing: 16) {
                Text("WORD-OFF!")
                    .font(.system(size: 40, weight: .black, design: .rounded))
                    .foregroundColor(Theme.tileFace)
                ProgressView()
                    .tint(.white)
            }
        }
    }
}
