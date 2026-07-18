import SwiftUI
import AuthenticationServices

struct AuthView: View {
    @EnvironmentObject var app: AppState
    @State private var username = ""
    @State private var country = Locale.current.region?.identifier ?? "US"
    @State private var needsProfile = false
    @State private var errorMessage: String?
    @State private var busy = false

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            ScrollView {
                VStack(spacing: 24) {
                    logo
                    if needsProfile {
                        profileForm
                    } else {
                        credentialsForm
                    }
                    if let errorMessage {
                        Text(errorMessage)
                            .font(.footnote)
                            .foregroundColor(.yellow)
                            .multilineTextAlignment(.center)
                    }
                }
                .padding(24)
            }
        }
        .onAppear {
            if app.session != nil && app.profile == nil {
                needsProfile = true
            }
        }
    }

    private var logo: some View {
        VStack(spacing: 8) {
            HStack(spacing: 3) {
                ForEach(Array("WORDED".enumerated()), id: \.offset) { _, letter in
                    TileView(letter: letter, size: 34)
                }
            }
            Text("Quickfire word battles")
                .font(.system(.subheadline, design: .rounded))
                .foregroundColor(Theme.subtleText)
        }
        .padding(.top, 40)
    }

    private var credentialsForm: some View {
        VStack(spacing: 14) {
            if app.isLocalMode {
                Text("Pick a username to get started")
                    .font(.system(.headline, design: .rounded))
                    .foregroundColor(Theme.tileText)
                TextField("Username", text: $username)
                    .textFieldStyle(.roundedBorder)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                countryPicker
                Button("Let's Play!") {
                    submitLocal()
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(username.count < 3)
            } else {
                Text("Sign in to play online, challenge friends, and climb the leaderboards.")
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundColor(Theme.tileText.opacity(0.7))
                    .multilineTextAlignment(.center)

                SignInWithAppleButton(.signIn) { request in
                    request.requestedScopes = [.email]
                } onCompletion: { result in
                    Task { await handleApple(result) }
                }
                .signInWithAppleButtonStyle(.white)
                .frame(height: 50)
                .cornerRadius(14)
            }
        }
        .panel()
    }

    private var profileForm: some View {
        VStack(spacing: 14) {
            Text("Choose your username")
                .font(.system(.headline, design: .rounded))
                .foregroundColor(Theme.tileText)
            Text("One last step — this is how friends find you in Worded.")
                .font(.system(.caption, design: .rounded))
                .foregroundColor(Theme.tileText.opacity(0.6))
                .multilineTextAlignment(.center)
            TextField("Username", text: $username)
                .textFieldStyle(.roundedBorder)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            countryPicker
            Button("Save & Play") {
                Task { await saveProfile() }
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(busy || !isValidUsername(username))

            Button("Sign out") {
                app.signOut()
                needsProfile = false
            }
            .font(.system(.footnote, design: .rounded).weight(.bold))
            .foregroundColor(Theme.tileText.opacity(0.55))
            .padding(.top, 4)
        }
        .panel()
    }

    private func isValidUsername(_ name: String) -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard trimmed.count >= 3, trimmed.count <= 20 else { return false }
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_"))
        return trimmed.unicodeScalars.allSatisfy { allowed.contains($0) }
    }

    private var countryPicker: some View {
        Picker("Country", selection: $country) {
            ForEach(Locale.Region.isoRegions.map(\.identifier).sorted(), id: \.self) { code in
                Text("\(flag(code)) \(Locale.current.localizedString(forRegionCode: code) ?? code)")
                    .tag(code)
            }
        }
        .pickerStyle(.menu)
        .tint(Theme.accentDark)
    }

    private func flag(_ code: String) -> String {
        code.unicodeScalars.reduce("") { result, scalar in
            result + String(UnicodeScalar(127397 + scalar.value) ?? " ")
        }
    }

    private func submitLocal() {
        guard WordDictionary.shared.isCleanUsername(username) else {
            errorMessage = "That username isn't allowed."
            return
        }
        app.completeLocalSignIn(username: username, country: country)
    }

    private func handleApple(_ result: Result<ASAuthorization, Error>) async {
        guard case .success(let auth) = result,
              let credential = auth.credential as? ASAuthorizationAppleIDCredential,
              let tokenData = credential.identityToken,
              let token = String(data: tokenData, encoding: .utf8) else {
            errorMessage = "Apple sign-in failed."
            return
        }
        do {
            app.session = try await SupabaseClient.shared.signInWithApple(idToken: token)
            await app.loadProfile()
            needsProfile = app.profile == nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func saveProfile() async {
        let chosen = username.trimmingCharacters(in: .whitespaces)
        guard isValidUsername(chosen) else {
            errorMessage = "Username must be 3–20 characters (letters, numbers, underscore)."
            return
        }
        guard WordDictionary.shared.isCleanUsername(chosen) else {
            errorMessage = "That username isn't allowed."
            return
        }
        busy = true
        defer { busy = false }
        errorMessage = nil
        do {
            try await app.createProfile(username: chosen, country: country)
            needsProfile = false
        } catch {
            errorMessage = "Username may be taken. Try another."
        }
    }
}
