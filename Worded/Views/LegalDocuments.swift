import SwiftUI

enum LegalDocument: String, Identifiable {
    case privacyPolicy
    case termsOfService

    var id: String { rawValue }

    var title: String {
        switch self {
        case .privacyPolicy: return "Privacy Policy"
        case .termsOfService: return "Terms of Service"
        }
    }

    var bodyText: String {
        switch self {
        case .privacyPolicy: return LegalCopy.privacyPolicy
        case .termsOfService: return LegalCopy.termsOfService
        }
    }
}

enum LegalCopy {
    static let privacyPolicy = """
    Privacy Policy for Worded

    Last updated: July 16, 2026

    This Privacy Policy explains how Worded (“the App”) handles information when you use the App. Worded is a word game. We do not show ads, and we do not sell your personal information.

    1. Information we collect

    Account information. If you sign in with Sign in with Apple, we receive an identifier from Apple so we can keep you signed in. Apple may provide a name or email depending on the options you choose in Apple’s Sign in with Apple sheet. You also choose a username (and optionally a country) in the App.

    Gameplay data. We store game-related data needed to run the App, such as match results, daily challenge scores, leaderboard entries, lives/streaks, badge progress, friendships, friend requests, and friend challenge state. If online features are enabled, this data may be stored on our cloud database (Supabase) associated with your account. A rough “last active” timestamp may be stored so friends can see when you are online in the App.

    Device preferences. Settings you choose in the App (for example notification, sound, and haptic preferences) are stored on your device.

    Notifications. If you allow notifications, the App may schedule local reminders on your device (for example a daily challenge reminder, or an optional alert when another player is waiting for a Quick Match). With your permission, we may also send remote push notifications for social events such as friend challenges and friend requests. Remote push uses an Apple device token stored with your account so we can deliver those alerts when the App is not open. You can turn notifications off in the App’s Settings or in iOS Settings.

    2. How we use information

    We use this information to:
    • create and maintain your account and username;
    • operate matches, daily challenges, leaderboards, and related features;
    • restore your progress across sessions;
    • send the notifications you enable;
    • maintain security and prevent abuse;
    • improve the App.

    3. Sign in with Apple

    Worded uses Sign in with Apple for authentication. We do not receive or store your Apple ID password. We do not use your Apple account for advertising. You can manage Sign in with Apple access in your Apple ID settings on your device.

    4. Sharing

    We do not sell personal information. We do not share personal information with advertisers.

    We may use service providers that process data on our behalf to host the App’s backend (currently Supabase) and deliver the App through Apple. Those providers process data under their own terms and only as needed to provide their services.

    We may disclose information if required by law, or to protect the rights, safety, and integrity of the App and its users.

    Other players may see limited public game information, such as your username, leaderboard scores, and badges shown in match intros.

    5. Data retention

    We keep account and gameplay data while your account is active and as needed to operate the App. You can delete your account in the App under Settings → Delete Account, which removes your account and associated game data from our systems, except where we must retain information for legal, security, or fraud-prevention reasons.

    6. Children’s privacy

    Worded is not directed to children under 13. If you believe we have collected personal information from a child under 13, contact us and we will take appropriate steps to delete it.

    7. Your choices

    You can:
    • control notification, sound, and haptic preferences in Settings;
    • disable system notifications for Worded in iOS Settings;
    • sign out of the App;
    • delete your account in Settings.

    8. Security

    We take reasonable measures to protect information. No method of transmission or storage is completely secure.

    9. International processing

    Your information may be processed in the United States or other countries where our service providers operate.

    10. Changes

    We may update this Privacy Policy from time to time. The “Last updated” date will change when we do. Continued use of the App after an update means you acknowledge the revised policy.

    11. Contact

    For privacy questions or account deletion requests, contact the developer of Worded through the App’s App Store page.
    """

    static let termsOfService = """
    Terms of Service for Worded

    Last updated: July 16, 2026

    These Terms of Service (“Terms”) govern your use of Worded (the “App”). By downloading or using the App, you agree to these Terms. If you do not agree, do not use the App.

    1. The App

    Worded is a mobile word game that may include daily challenges, online matches, friend challenges, optional in-app purchases (such as premium access or day passes), and related features. Features may change over time.

    2. Eligibility

    You must be at least 13 years old (or the minimum age required in your country) to use the App. If you use the App on behalf of someone else, you represent that you have authority to accept these Terms for them.

    3. Accounts

    You may need to sign in (including with Sign in with Apple) and choose a username. You are responsible for activity under your account and for keeping access to your device secure. Usernames must not be offensive, infringing, or impersonating others. We may reclaim or require changes to usernames that violate these Terms.

    4. License

    We grant you a personal, non-exclusive, non-transferable, revocable license to use the App for entertainment on devices you own or control, subject to these Terms and Apple’s App Store terms.

    You may not copy, modify, distribute, reverse engineer, or create derivative works of the App except as allowed by law; cheat, automate, or interfere with matchmaking, scoring, leaderboards, or other users; or use the App for unlawful purposes.

    5. Virtual items and purchases

    The App may offer lives, streaks, premium access, day passes, or other virtual features. These have no cash value, are not transferable, and may be modified or discontinued. Purchases are processed by Apple. Refund requests are handled under Apple’s refund policies.

    6. Online play and community

    Online features require an internet connection and may be unavailable at times. Be respectful. Do not harass other players or attempt to exploit the service. We may suspend or terminate access for abuse, cheating, or violations of these Terms.

    7. Notifications

    With your permission, the App may send notifications, including a daily challenge reminder, an optional alert when someone is waiting for a Quick Match, and remote push alerts for friend challenges and friend requests. You can turn these off in the App’s Settings or in iOS Settings. Optional Quick Match waiting alerts are limited so we do not send more than one per hour.

    8. Intellectual property

    The App, including its design, text, graphics, and software, is owned by the developer of Worded or its licensors and is protected by intellectual property laws. These Terms do not transfer ownership to you.

    9. Disclaimer

    THE APP IS PROVIDED “AS IS” AND “AS AVAILABLE.” TO THE MAXIMUM EXTENT PERMITTED BY LAW, WE DISCLAIM ALL WARRANTIES, EXPRESS OR IMPLIED, INCLUDING MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE, AND NON-INFRINGEMENT. We do not guarantee uninterrupted or error-free service, or that scores, matchmaking, or leaderboards will always be accurate.

    10. Limitation of liability

    TO THE MAXIMUM EXTENT PERMITTED BY LAW, THE DEVELOPER OF WORDED WILL NOT BE LIABLE FOR INDIRECT, INCIDENTAL, SPECIAL, CONSEQUENTIAL, OR PUNITIVE DAMAGES, OR FOR LOST PROFITS, DATA, OR GOODWILL, ARISING FROM YOUR USE OF THE APP. OUR TOTAL LIABILITY FOR ANY CLAIM RELATING TO THE APP WILL NOT EXCEED THE GREATER OF (A) THE AMOUNT YOU PAID US FOR THE APP OR IN-APP PURCHASES IN THE 12 MONTHS BEFORE THE CLAIM, OR (B) USD $10.

    Some jurisdictions do not allow certain limitations; in those places, our liability is limited to the fullest extent allowed.

    11. Termination

    You may stop using the App at any time. We may suspend or end access if you violate these Terms or if we discontinue the App. Sections that by nature should survive (including license limitations, disclaimer, and liability) will survive termination.

    12. Changes to the Terms

    We may update these Terms. The “Last updated” date will change when we do. Continued use after changes means you accept the updated Terms.

    13. Apple’s role

    You acknowledge that these Terms are between you and the developer of Worded, not Apple. Apple is not responsible for the App or its content. Apple has no obligation to provide maintenance or support for the App. To the extent any warranty applies and is not effectively disclaimed, Apple may refund the purchase price of the App if applicable under Apple’s policies; Apple has no other warranty obligation. Apple is not responsible for addressing claims relating to the App, including product liability, legal/regulatory compliance, or consumer protection claims. Apple is not responsible for investigating, defending, settling, or discharging third-party intellectual property infringement claims related to the App. Apple and Apple’s subsidiaries are third-party beneficiaries of these Terms and may enforce them against you.

    14. Contact

    Questions about these Terms can be sent through the App’s App Store page.
    """
}

struct LegalDocumentView: View {
    let document: LegalDocument
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.background.ignoresSafeArea()
                ScrollView {
                    Text(document.bodyText)
                        .font(.system(.body, design: .rounded))
                        .foregroundColor(Theme.tileText)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(20)
                        .background(
                            RoundedRectangle(cornerRadius: 16)
                                .fill(Theme.panel)
                        )
                        .padding()
                }
            }
            .navigationTitle(document.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
    }
}
