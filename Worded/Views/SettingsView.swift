import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var settings = SettingsStore.shared
    @State private var legalDocument: LegalDocument?
    @State private var confirmDeleteAccount = false
    @State private var deleteBusy = false
    @State private var deleteError: String?

    /// Onboarding tour: focus someone-waiting prefs and show a Done CTA.
    var someoneWaitingOnboarding: Bool = false
    var onSomeoneWaitingOnboardingDone: (() -> Void)? = nil

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.background.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 16) {
                        if someoneWaitingOnboarding {
                            onboardingBanner
                        }
                        notificationsCard
                        if !someoneWaitingOnboarding {
                            feedbackCard
                            legalCard
                            accountCard
                            versionFooter
                        } else {
                            Button("Done") {
                                onSomeoneWaitingOnboardingDone?()
                                dismiss()
                            }
                            .buttonStyle(PrimaryButtonStyle())
                            .padding(.top, 8)
                        }
                    }
                    .padding()
                }
            }
            .navigationTitle(someoneWaitingOnboarding ? "Notifications" : "Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(someoneWaitingOnboarding ? "Done" : "Close") {
                        if someoneWaitingOnboarding {
                            onSomeoneWaitingOnboardingDone?()
                        }
                        dismiss()
                    }
                }
            }
            .sheet(item: $legalDocument) { doc in
                LegalDocumentView(document: doc)
            }
            .onChange(of: settings.notificationsEnabled) { _, enabled in
                Task {
                    if enabled {
                        await MatchmakingNotifications.requestOrOpenSettingsIfDenied()
                        await PushRegistration.requestAuthorizationAndRegister()
                    } else {
                        await PushRegistration.clearTokenFromServer()
                    }
                    await app.refreshDailyReminderNotification()
                }
                app.refreshSomeoneWaitingPolling()
            }
            .onChange(of: settings.notifyWhenSomeoneWaiting) { _, enabled in
                if enabled {
                    Task {
                        // Turning this on without OS permission → prompt again / open Settings.
                        if !settings.notificationsEnabled {
                            settings.notificationsEnabled = true
                        } else {
                            await MatchmakingNotifications.requestOrOpenSettingsIfDenied()
                        }
                    }
                }
                app.refreshSomeoneWaitingPolling()
            }
            .alert("Delete account?", isPresented: $confirmDeleteAccount) {
                Button("Delete Account", role: .destructive) {
                    Task { await performDeleteAccount() }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This permanently deletes your Worded account, scores, and online data. This can’t be undone.")
            }
            .alert("Couldn’t delete account", isPresented: Binding(
                get: { deleteError != nil },
                set: { if !$0 { deleteError = nil } }
            )) {
                Button("OK", role: .cancel) { deleteError = nil }
            } message: {
                Text(deleteError ?? "")
            }
        }
    }

    private var onboardingBanner: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Stay in the loop")
                .font(.system(.title3, design: .rounded).weight(.black))
                .foregroundColor(Theme.tileText)
            Text("You can also get notified when someone else is looking for a game. Set how many of those alerts you want per day.")
                .font(.system(.subheadline, design: .rounded))
                .foregroundColor(Theme.tileText.opacity(0.7))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14).fill(Theme.panel))
    }

    private var notificationsCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("NOTIFICATIONS")
                .font(.system(.caption, design: .rounded).weight(.black))
                .foregroundColor(Theme.tileText.opacity(0.5))

            Toggle(isOn: $settings.notificationsEnabled) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Enable notifications")
                        .font(.system(.subheadline, design: .rounded).weight(.bold))
                        .foregroundColor(Theme.tileText)
                    Text("Daily challenge reminder at 8:00pm if you haven’t played yet, plus match alerts.")
                        .font(.system(.caption2, design: .rounded))
                        .foregroundColor(Theme.tileText.opacity(0.55))
                }
            }
            .tint(Theme.accent)

            Toggle(isOn: $settings.notifyWhenSomeoneWaiting) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Someone’s looking for a match")
                        .font(.system(.subheadline, design: .rounded).weight(.bold))
                        .foregroundColor(Theme.tileText)
                    Text("Get notified when another player is waiting for Quick Match.")
                        .font(.system(.caption2, design: .rounded))
                        .foregroundColor(Theme.tileText.opacity(0.55))
                }
            }
            .tint(Theme.accent)
            .disabled(!settings.notificationsEnabled)
            .opacity(settings.notificationsEnabled ? 1 : 0.45)

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Max alerts per day")
                        .font(.system(.subheadline, design: .rounded).weight(.bold))
                        .foregroundColor(Theme.tileText)
                    Spacer()
                    Text("\(settings.maxSomeoneWaitingPerDay)")
                        .font(.system(.subheadline, design: .rounded).weight(.black))
                        .foregroundColor(Theme.accentDark)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(Theme.accent.opacity(0.25)))
                }
                Slider(
                    value: Binding(
                        get: { Double(settings.maxSomeoneWaitingPerDay) },
                        set: { settings.maxSomeoneWaitingPerDay = Int($0.rounded()) }),
                    in: 1...10,
                    step: 1)
                .tint(Theme.accent)
                .disabled(!settings.notificationsEnabled || !settings.notifyWhenSomeoneWaiting)
                .opacity(settings.notificationsEnabled && settings.notifyWhenSomeoneWaiting ? 1 : 0.45)

                Text("We’ll notify you at most this many times per day when someone is waiting to play.")
                    .font(.system(.caption2, design: .rounded))
                    .foregroundColor(Theme.tileText.opacity(0.55))
            }
        }
        .panel()
    }

    private var feedbackCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("SOUND & HAPTICS")
                .font(.system(.caption, design: .rounded).weight(.black))
                .foregroundColor(Theme.tileText.opacity(0.5))

            Toggle(isOn: $settings.soundsEnabled) {
                Text("Sounds")
                    .font(.system(.subheadline, design: .rounded).weight(.bold))
                    .foregroundColor(Theme.tileText)
            }
            .tint(Theme.accent)

            Toggle(isOn: $settings.hapticsEnabled) {
                Text("Vibrations")
                    .font(.system(.subheadline, design: .rounded).weight(.bold))
                    .foregroundColor(Theme.tileText)
            }
            .tint(Theme.accent)
        }
        .panel()
    }

    private var legalCard: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("LEGAL")
                .font(.system(.caption, design: .rounded).weight(.black))
                .foregroundColor(Theme.tileText.opacity(0.5))
                .padding(.bottom, 6)

            legalRow(title: "Privacy Policy", document: .privacyPolicy)
            Divider().overlay(Theme.tileText.opacity(0.12))
            legalRow(title: "Terms of Service", document: .termsOfService)
        }
        .panel()
    }

    private func legalRow(title: String, document: LegalDocument) -> some View {
        Button {
            legalDocument = document
        } label: {
            HStack {
                Text(title)
                    .font(.system(.subheadline, design: .rounded).weight(.bold))
                    .foregroundColor(Theme.tileText)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(Theme.tileText.opacity(0.35))
            }
            .padding(.vertical, 8)
        }
        .buttonStyle(.plain)
    }

    private var accountCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("ACCOUNT")
                .font(.system(.caption, design: .rounded).weight(.black))
                .foregroundColor(Theme.tileText.opacity(0.5))

            Button {
                confirmDeleteAccount = true
            } label: {
                HStack {
                    if deleteBusy {
                        ProgressView()
                    }
                    Text(deleteBusy ? "Deleting…" : "Delete Account")
                        .font(.system(.subheadline, design: .rounded).weight(.bold))
                        .foregroundColor(Theme.lose)
                    Spacer()
                }
            }
            .buttonStyle(.plain)
            .disabled(deleteBusy)

            Text("Permanently remove your account and associated game data from Worded.")
                .font(.system(.caption2, design: .rounded))
                .foregroundColor(Theme.tileText.opacity(0.55))
        }
        .panel()
    }

    private var versionFooter: some View {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
        return Text("Worded · Version \(version)")
            .font(.system(.caption2, design: .rounded).weight(.semibold))
            .foregroundColor(Theme.subtleText)
            .frame(maxWidth: .infinity)
            .padding(.top, 8)
    }

    private func performDeleteAccount() async {
        deleteBusy = true
        deleteError = nil
        do {
            try await app.deleteAccount()
            dismiss()
        } catch {
            deleteError = error.localizedDescription
        }
        deleteBusy = false
    }
}
