import SwiftUI
import AuthenticationServices

struct AuthView: View {
    @EnvironmentObject var app: AppState
    @State private var email = ""
    @State private var password = ""
    @State private var username = ""
    @State private var country = Locale.current.region?.identifier ?? "US"
    @State private var isSigningUp = true
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
    }

    private var logo: some View {
        VStack(spacing: 8) {
            HStack(spacing: 3) {
                ForEach(Array("WORD".enumerated()), id: \.offset) { _, letter in
                    TileView(letter: letter, size: 34)
                }
                Text("–")
                    .font(.system(size: 26, weight: .black))
                    .foregroundColor(.white)
                ForEach(Array("OFF!".enumerated()), id: \.offset) { _, letter in
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
                Picker("Mode", selection: $isSigningUp) {
                    Text("Sign Up").tag(true)
                    Text("Log In").tag(false)
                }
                .pickerStyle(.segmented)

                TextField("Email", text: $email)
                    .textFieldStyle(.roundedBorder)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                SecureField("Password", text: $password)
                    .textFieldStyle(.roundedBorder)

                Button(isSigningUp ? "Create Account" : "Log In") {
                    Task { await submitEmail() }
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(busy || email.isEmpty || password.count < 6)

                SignInWithAppleButton(.signIn) { request in
                    request.requestedScopes = [.email]
                } onCompletion: { result in
                    Task { await handleApple(result) }
                }
                .frame(height: 48)
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
            TextField("Username", text: $username)
                .textFieldStyle(.roundedBorder)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            countryPicker
            Button("Save & Play") {
                Task { await saveProfile() }
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(busy || username.count < 3)
        }
        .panel()
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

    private func submitEmail() async {
        busy = true
        defer { busy = false }
        errorMessage = nil
        do {
            if isSigningUp {
                app.session = try await SupabaseClient.shared.signUp(email: email, password: password)
                needsProfile = true
            } else {
                app.session = try await SupabaseClient.shared.signIn(email: email, password: password)
                await app.loadProfile()
                if app.profile == nil { needsProfile = true }
            }
        } catch {
            errorMessage = error.localizedDescription
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
        do {
            app.session = try await SupabaseClient.shared.signInWithApple(idToken: token)
            await app.loadProfile()
            if app.profile == nil { needsProfile = true }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func saveProfile() async {
        guard WordDictionary.shared.isCleanUsername(username) else {
            errorMessage = "That username isn't allowed."
            return
        }
        busy = true
        defer { busy = false }
        do {
            try await app.createProfile(username: username, country: country)
            needsProfile = false
        } catch {
            errorMessage = "Username may be taken. Try another."
        }
    }
}
