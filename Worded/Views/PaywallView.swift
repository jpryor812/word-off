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
                    VStack(spacing: 18) {
                        header
                        monthlyCard
                        dayPassCard
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

    private var header: some View {
        VStack(spacing: 8) {
            Image(systemName: "crown.fill")
                .font(.system(size: 44))
                .foregroundColor(Theme.accent)
                .padding(.top, 16)
            Text("Level Up Your Game")
                .font(.system(.title, design: .rounded).weight(.black))
                .foregroundColor(.white)
            Text("Play without limits")
                .font(.system(.subheadline, design: .rounded))
                .foregroundColor(Theme.subtleText)
        }
    }

    private var monthlyProduct: Product? {
        app.entitlements.products.first { $0.id == EntitlementsManager.premiumID }
    }

    private var dayPassProduct: Product? {
        app.entitlements.products.first { $0.id == EntitlementsManager.dailyPassID }
    }

    private var monthlyCard: some View {
        VStack(spacing: 14) {
            HStack {
                Text("MONTHLY PASS")
                    .font(.system(.headline, design: .rounded).weight(.black))
                    .foregroundColor(Theme.tileText)
                Spacer()
                Text("BEST VALUE")
                    .font(.system(.caption2, design: .rounded).weight(.black))
                    .foregroundColor(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(Theme.accent))
            }

            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(monthlyProduct?.displayPrice ?? "$4.99")
                    .font(.system(size: 40, weight: .black, design: .rounded))
                    .foregroundColor(Theme.accentDark)
                Text("/month")
                    .font(.system(.subheadline, design: .rounded).weight(.bold))
                    .foregroundColor(Theme.tileText.opacity(0.6))
                Spacer()
            }

            VStack(alignment: .leading, spacing: 10) {
                benefit("Unlimited PvP games")
                benefit("Play all daily challenges")
                benefit("No ads")
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            purchaseButton(product: monthlyProduct, fallbackLabel: "Go Premium", color: Theme.accent)
        }
        .panel()
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(Theme.accent, lineWidth: 2.5)
        )
    }

    private var dayPassCard: some View {
        VStack(spacing: 14) {
            HStack {
                Text("DAY PASS")
                    .font(.system(.headline, design: .rounded).weight(.black))
                    .foregroundColor(Theme.tileText)
                Spacer()
            }

            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(dayPassProduct?.displayPrice ?? "$0.99")
                    .font(.system(size: 40, weight: .black, design: .rounded))
                    .foregroundColor(Theme.tileText)
                Text("one time")
                    .font(.system(.subheadline, design: .rounded).weight(.bold))
                    .foregroundColor(Theme.tileText.opacity(0.6))
                Spacer()
            }

            VStack(alignment: .leading, spacing: 10) {
                benefit("24 hours of everything in the Monthly Pass")
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            purchaseButton(product: dayPassProduct, fallbackLabel: "Get Day Pass", color: Theme.backgroundLight)
        }
        .panel()
    }

    @ViewBuilder
    private func purchaseButton(product: Product?, fallbackLabel: String, color: Color) -> some View {
        if let product {
            Button {
                Task {
                    await app.entitlements.purchase(product)
                    if app.entitlements.isPremium { dismiss() }
                }
            } label: {
                Text(fallbackLabel)
            }
            .buttonStyle(PrimaryButtonStyle(color: color))
        } else {
            Text("Available once App Store Connect is configured")
                .font(.system(.caption, design: .rounded))
                .foregroundColor(Theme.tileText.opacity(0.5))
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
            promoMessage = "24 hours of Premium unlocked — enjoy!"
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
