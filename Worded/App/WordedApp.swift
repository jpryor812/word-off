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

    @State private var authOffset: CGFloat = 0
    @State private var homeOffset: CGFloat = 0
    @State private var showHomeLayer = false
    @State private var showAuthLayer = true
    @State private var hasPlayedHomeEntrance = false

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Theme.background.ignoresSafeArea()

                if app.isLoading {
                    LaunchLoadingView()
                } else if app.onboardingStore.needsWelcomeIntro {
                    WelcomeIntroView {
                        app.onboardingStore.completeWelcomeIntro()
                        syncLayersForCurrentAuthState(screenHeight: geo.size.height)
                    }
                } else {
                    if showHomeLayer {
                        HomeView()
                            .environmentObject(app)
                            .offset(y: homeOffset)
                    }

                    if showAuthLayer && (app.session == nil || app.profile == nil || authOffset > 0) {
                        AuthView()
                            .environmentObject(app)
                            .offset(y: authOffset)
                            .zIndex(1)
                    }
                }

                if showHomeLayer, app.profile != nil, app.matchmakingBanner != .hidden {
                    VStack {
                        MatchmakingBanner()
                            .environmentObject(app)
                        Spacer()
                    }
                    .padding(.top, geo.safeAreaInsets.top)
                    .zIndex(20)
                }

                if app.showAIDifficultyPicker {
                    AIDifficultyPickerOverlay()
                        .environmentObject(app)
                        .zIndex(40)
                }
            }
            .onAppear {
                syncLayersForCurrentAuthState(screenHeight: geo.size.height)
            }
            .onChange(of: app.isLoading) { _, loading in
                guard !loading else { return }
                syncLayersForCurrentAuthState(screenHeight: geo.size.height)
            }
            .onChange(of: app.profile?.id) { oldID, newID in
                guard !app.isLoading, !app.onboardingStore.needsWelcomeIntro else { return }
                if oldID == nil, newID != nil, !hasPlayedHomeEntrance {
                    playHomeEntrance(screenHeight: geo.size.height)
                } else {
                    syncLayersForCurrentAuthState(screenHeight: geo.size.height)
                }
            }
            .onChange(of: app.session?.userId) { _, _ in
                guard !app.isLoading, !app.onboardingStore.needsWelcomeIntro else { return }
                if app.profile == nil {
                    showAuthLayer = true
                    authOffset = 0
                    if !hasPlayedHomeEntrance {
                        showHomeLayer = false
                    }
                }
            }
        }
        .task { await app.bootstrap() }
        .onOpenURL { url in
            Task { await app.handleIncomingURL(url) }
        }
        .onChange(of: scenePhase) { _, phase in
            app.handleScenePhase(phase)
            if phase == .active {
                app.recordActivity()
                app.enforceSessionRetention()
                app.challengePolling(active: true)
            } else {
                app.challengePolling(active: false)
            }
        }
    }

    private func syncLayersForCurrentAuthState(screenHeight: CGFloat) {
        if app.profile != nil {
            showHomeLayer = true
            homeOffset = 0
            showAuthLayer = false
            authOffset = 0
            hasPlayedHomeEntrance = true
        } else {
            showHomeLayer = false
            homeOffset = screenHeight
            showAuthLayer = true
            authOffset = 0
        }
    }

    private func playHomeEntrance(screenHeight: CGFloat) {
        hasPlayedHomeEntrance = true
        app.onboardingStore.beginDeferredHomeEntrance()

        showHomeLayer = true
        homeOffset = screenHeight
        showAuthLayer = true
        authOffset = 0

        // Auth slides down; home slides up over the teal background.
        withAnimation(.easeInOut(duration: 0.55)) {
            authOffset = screenHeight
            homeOffset = 0
        }

        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(600))
            showAuthLayer = false
            authOffset = 0
            // Brief beat so home can finish layout before the first callout.
            try? await Task.sleep(for: .milliseconds(120))
            app.onboardingStore.finishDeferredHomeEntrance()
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
