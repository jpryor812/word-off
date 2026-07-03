import SwiftUI
import StoreKit

struct PaywallView: View {
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var promoCode = ""
    @State private var promoMessage: String?
    @State private var promoSucceeded = false

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.background.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 20) {
                        Image(systemName: "crown.fill")
                            .font(.system(size: 52))
                            .foregroundColor(Theme.accent)
                            .padding(.top, 30)

                        Text("Word-Off! Premium")
                            .font(.system(.title, design: .rounded).weight(.black))
                            .foregroundColor(.white)

                        VStack(alignment: .leading, spacing: 12) {
                            benefit("All 5 daily puzzles, every day")
                            benefit("Unlimited online games — no lives")
                            benefit("No ads, ever")
                        }
                        .panel()

                        productButtons

                        promoSection

                        Button("Restore Purchases") {
                            Task { await app.entitlements.restorePurchases() }
                        }
                        .font(.system(.subheadline, design: .rounded))
                        .foregroundColor(Theme.subtleText)

                        if let error = app.entitlements.purchaseError {
                            Text(error)
                                .font(.footnote)
                                .foregroundColor(.yellow)
                        }
                    }
                    .padding()
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
    }

    @ViewBuilder
    private var productButtons: some View {
        if app.entitlements.products.isEmpty {
            VStack(spacing: 10) {
                Text("Premium — $5.99/month")
                Text("Day Pass — $1.99")
                Text("(Purchases available once App Store Connect is configured)")
                    .font(.system(.caption, design: .rounded))
            }
            .font(.system(.subheadline, design: .rounded).weight(.bold))
            .foregroundColor(Theme.subtleText)
        } else {
            ForEach(app.entitlements.products, id: \.id) { product in
                Button {
                    Task {
                        await app.entitlements.purchase(product)
                        if app.entitlements.isPremium { dismiss() }
                    }
                } label: {
                    VStack(spacing: 2) {
                        Text(product.id == EntitlementsManager.premiumID
                             ? "Go Premium — \(product.displayPrice)/month"
                             : "Day Pass — \(product.displayPrice) today only")
                    }
                }
                .buttonStyle(PrimaryButtonStyle(
                    color: product.id == EntitlementsManager.premiumID ? Theme.accent : Theme.backgroundLight))
            }
        }
    }

    private var promoSection: some View {
        VStack(spacing: 10) {
            Text("Have a promo code?")
                .font(.system(.subheadline, design: .rounded).weight(.bold))
                .foregroundColor(Theme.tileText)

            if app.entitlements.hasPromoPremium {
                Label("Promo premium active", systemImage: "checkmark.seal.fill")
                    .font(.system(.subheadline, design: .rounded).weight(.bold))
                    .foregroundColor(Theme.win)
            } else {
                HStack {
                    TextField("Promo code", text: $promoCode)
                        .textFieldStyle(.roundedBorder)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Button("Apply") { redeemPromo() }
                        .buttonStyle(.borderedProminent)
                        .tint(Theme.accent)
                        .disabled(promoCode.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }

            if let promoMessage {
                Text(promoMessage)
                    .font(.system(.caption, design: .rounded).weight(.bold))
                    .foregroundColor(promoSucceeded ? Theme.win : Theme.lose)
            }
        }
        .panel()
    }

    private func redeemPromo() {
        if app.entitlements.redeemPromo(code: promoCode) {
            promoSucceeded = true
            promoMessage = "Premium unlocked — enjoy!"
            promoCode = ""
        } else {
            promoSucceeded = false
            promoMessage = "That code isn't valid."
        }
    }

    private func benefit(_ text: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(Theme.win)
            Text(text)
                .font(.system(.subheadline, design: .rounded).weight(.semibold))
                .foregroundColor(Theme.tileText)
        }
    }
}
