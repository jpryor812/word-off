import SwiftUI
import AuthenticationServices

/// First-launch welcome: scrambled tiles settle into WELCOME / TO / WORDED, then Sign in with Apple.
struct WelcomeIntroView: View {
    @EnvironmentObject var app: AppState
    var onContinue: () -> Void

    private let words = ["WELCOME", "TO", "WORDED"]
    private let tileSize: CGFloat = 40
    private let tileSpacing: CGFloat = 5
    private let lineSpacing: CGFloat = 16

    @State private var formedLines = 0
    @State private var showButton = false
    @State private var scrambleOffsets: [CGSize] = []
    @State private var scrambleRotations: [Double] = []
    @State private var appeared = false
    @State private var errorMessage: String?
    @State private var busy = false

    private var letters: [WelcomeLetter] {
        var result: [WelcomeLetter] = []
        var id = 0
        for (line, word) in words.enumerated() {
            for (col, char) in Array(word).enumerated() {
                result.append(WelcomeLetter(id: id, char: char, line: line, col: col))
                id += 1
            }
        }
        return result
    }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Theme.background.ignoresSafeArea()

                ForEach(letters) { letter in
                    TileView(letter: letter.char, size: tileSize)
                        .rotationEffect(.degrees(rotation(for: letter)))
                        .position(position(for: letter, in: geo.size))
                        .opacity(appeared ? 1 : 0)
                }

                VStack {
                    Spacer()
                    if showButton {
                        VStack(spacing: 12) {
                            if let errorMessage {
                                Text(errorMessage)
                                    .font(.footnote)
                                    .foregroundColor(.yellow)
                                    .multilineTextAlignment(.center)
                            }

                            if app.isLocalMode {
                                Button("Get started", action: onContinue)
                                    .buttonStyle(PrimaryButtonStyle())
                            } else {
                                SignInWithAppleButton(.signIn) { request in
                                    request.requestedScopes = [.email]
                                } onCompletion: { result in
                                    Task { await handleApple(result) }
                                }
                                .signInWithAppleButtonStyle(.white)
                                .frame(height: 50)
                                .cornerRadius(14)
                                .disabled(busy)
                                .opacity(busy ? 0.7 : 1)
                            }
                        }
                        .padding(.horizontal, 32)
                        .padding(.bottom, max(geo.safeAreaInsets.bottom, 24) + 88)
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                    }
                }
            }
        }
        .onAppear {
            seedScramble()
            runAnimation()
        }
    }

    private func seedScramble() {
        var offsets: [CGSize] = []
        var rotations: [Double] = []
        var generator = SeededRandom(seed: 42)
        for _ in letters {
            offsets.append(
                CGSize(
                    width: CGFloat.random(in: -72...72, using: &generator),
                    height: CGFloat.random(in: -56...56, using: &generator)
                )
            )
            rotations.append(Double.random(in: -28...28, using: &generator))
        }
        scrambleOffsets = offsets
        scrambleRotations = rotations
    }

    private func runAnimation() {
        withAnimation(.easeOut(duration: 0.35)) {
            appeared = true
        }

        // Hold the messy pile, then form one word at a time (~3.6s total before the button).
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(900))
            for line in 0..<words.count {
                withAnimation(.spring(response: 0.55, dampingFraction: 0.82)) {
                    formedLines = line + 1
                }
                try? await Task.sleep(for: .milliseconds(line == words.count - 1 ? 550 : 700))
            }
            withAnimation(.easeOut(duration: 0.35)) {
                showButton = true
            }
        }
    }

    private func handleApple(_ result: Result<ASAuthorization, Error>) async {
        guard case .success(let auth) = result,
              let credential = auth.credential as? ASAuthorizationAppleIDCredential,
              let tokenData = credential.identityToken,
              let token = String(data: tokenData, encoding: .utf8) else {
            errorMessage = "Apple sign-in failed."
            return
        }
        busy = true
        defer { busy = false }
        errorMessage = nil
        do {
            app.session = try await SupabaseClient.shared.signInWithApple(idToken: token)
            await app.loadProfile()
            onContinue()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func rotation(for letter: WelcomeLetter) -> Double {
        guard letter.id < scrambleRotations.count else { return 0 }
        return letter.line < formedLines ? 0 : scrambleRotations[letter.id]
    }

    private func position(for letter: WelcomeLetter, in size: CGSize) -> CGPoint {
        if letter.line < formedLines {
            return finalPosition(for: letter, in: size)
        }
        let pileCenter = CGPoint(x: size.width / 2, y: size.height * 0.42)
        guard letter.id < scrambleOffsets.count else { return pileCenter }
        let offset = scrambleOffsets[letter.id]
        return CGPoint(x: pileCenter.x + offset.width, y: pileCenter.y + offset.height)
    }

    private func finalPosition(for letter: WelcomeLetter, in size: CGSize) -> CGPoint {
        let word = words[letter.line]
        let wordWidth = CGFloat(word.count) * tileSize
            + CGFloat(max(word.count - 1, 0)) * tileSpacing
        let blockHeight = CGFloat(words.count) * tileSize
            + CGFloat(words.count - 1) * lineSpacing
        // Leave room for the sign-in button along the bottom.
        let blockCenterY = size.height * 0.38
        let topY = blockCenterY - blockHeight / 2

        let lineY = topY + CGFloat(letter.line) * (tileSize + lineSpacing) + tileSize / 2
        let lineStartX = (size.width - wordWidth) / 2
        let x = lineStartX + CGFloat(letter.col) * (tileSize + tileSpacing) + tileSize / 2
        return CGPoint(x: x, y: lineY)
    }
}

private struct WelcomeLetter: Identifiable {
    let id: Int
    let char: Character
    let line: Int
    let col: Int
}
