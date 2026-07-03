import Foundation
import StoreKit

/// StoreKit 2 wrapper for the two products:
/// - `com.wordoff.premium.monthly` ($5.99/mo): all dailies, unlimited PvP, no ads
/// - `com.wordoff.dailypass` ($1.99 consumable): same benefits until local midnight
@MainActor
final class EntitlementsManager: ObservableObject {
    static let premiumID = "com.wordoff.premium.monthly"
    static let dailyPassID = "com.wordoff.dailypass"

    @Published private(set) var products: [Product] = []
    @Published private(set) var hasActiveSubscription = false
    @Published var purchaseError: String?

    private var dailyPassDay: String {
        get { UserDefaults.standard.string(forKey: "wordoff.dailyPass.day") ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: "wordoff.dailyPass.day") }
    }

    private var updatesTask: Task<Void, Never>?

    init() {
        updatesTask = Task { [weak self] in
            for await update in Transaction.updates {
                if let transaction = try? update.payloadValue {
                    await self?.handle(transaction: transaction)
                    await transaction.finish()
                }
            }
        }
    }

    deinit { updatesTask?.cancel() }

    var hasDailyPassToday: Bool {
        dailyPassDay == Self.localDayString()
    }

    /// Premium for gameplay purposes: subscription OR today's pass.
    var isPremium: Bool { hasActiveSubscription || hasDailyPassToday }

    private static func localDayString() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = .current
        return formatter.string(from: Date())
    }

    func refresh() async {
        do {
            products = try await Product.products(for: [Self.premiumID, Self.dailyPassID])
        } catch {
            // Products unavailable until App Store Connect is configured; free-tier rules apply.
        }
        await refreshSubscriptionStatus()
    }

    func refreshSubscriptionStatus() async {
        var active = false
        for await entitlement in Transaction.currentEntitlements {
            if let transaction = try? entitlement.payloadValue,
               transaction.productID == Self.premiumID,
               transaction.revocationDate == nil {
                active = true
            }
        }
        hasActiveSubscription = active
    }

    func purchase(_ product: Product) async {
        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                let transaction = try verification.payloadValue
                await handle(transaction: transaction)
                await transaction.finish()
            case .userCancelled, .pending:
                break
            @unknown default:
                break
            }
        } catch {
            purchaseError = error.localizedDescription
        }
    }

    private func handle(transaction: Transaction) async {
        switch transaction.productID {
        case Self.premiumID:
            hasActiveSubscription = transaction.revocationDate == nil
        case Self.dailyPassID:
            dailyPassDay = Self.localDayString()
            objectWillChange.send()
        default:
            break
        }
    }

    func restorePurchases() async {
        try? await AppStore.sync()
        await refreshSubscriptionStatus()
    }
}
