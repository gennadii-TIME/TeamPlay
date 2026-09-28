//
//  PremiumManager.swift
//  Lume
//
//  The single source of truth for TeamPlay Premium access, and the StoreKit 2
//  layer behind it (one-time lifetime unlock + a 30-day trial from the original
//  App Store download).
//
//  Business model: 30 days of full access from `AppTransaction.originalPurchaseDate`,
//  then a single non-consumable lifetime purchase. No subscriptions. Sideloaded /
//  self-compiled builds (`SIDE_LOAD`) stay fully unlocked.
//

import Foundation
import OSLog
import Security
import StoreKit
#if canImport(UIKit)
    import UIKit
#endif

// MARK: - Access model (pure, testable)

/// Resolved Premium access. `loading` is only used while StoreKit / AppTransaction
/// have not yet answered; after that the state is always one of the other three.
nonisolated enum PremiumAccessState: Equatable, Sendable {
    case loading
    case trial(until: Date)
    case purchased
    case expired
}

/// Clock / entitlement inputs for resolving access. Kept free of StoreKit so unit
/// tests can drive the trial window without a sandbox account.
nonisolated struct PremiumAccessInputs: Equatable, Sendable {
    /// Wall clock. Callers must already apply any anti-rollback clamp.
    var now: Date
    /// Verified `AppTransaction.originalPurchaseDate`, or nil when unavailable.
    var originalPurchaseDate: Date?
    /// True when a verified, non-revoked lifetime entitlement is present.
    var hasLifetimeEntitlement: Bool
}

/// Pure trial / purchase resolution. No UserDefaults — the trial anchor is always
/// the App Store original download date supplied by the caller.
nonisolated enum PremiumAccessResolver {
    /// Exactly thirty 24-hour days from the original download.
    static let trialDuration: TimeInterval = 30 * 24 * 60 * 60

    /// Advance the high-water mark so a clock rollback cannot reopen a trial that
    /// has already been observed as ended (or further along).
    static func advancedHighWater(previous: Date, now: Date) -> Date {
        max(previous, now)
    }

    static func resolve(_ inputs: PremiumAccessInputs) -> PremiumAccessState {
        if inputs.hasLifetimeEntitlement {
            return .purchased
        }
        guard let start = inputs.originalPurchaseDate else {
            return .expired
        }
        let end = start.addingTimeInterval(trialDuration)
        // Active on [start, end): day 0 and day 29 inclusive, exactly day 30 expired.
        if inputs.now < end {
            return .trial(until: end)
        }
        return .expired
    }

    static func hasFullAccess(_ state: PremiumAccessState) -> Bool {
        switch state {
        case .purchased, .trial:
            return true
        case .loading, .expired:
            return false
        }
    }
}

// MARK: - Dependencies (injectable for tests)

nonisolated struct PremiumStoreDependencies: Sendable {
    var now: @Sendable () -> Date
    /// Verified original App Store download date, or nil when unavailable / unverified.
    var fetchOriginalPurchaseDate: @Sendable () async -> Date?
    /// Product IDs with a verified, non-revoked current entitlement.
    var fetchEntitledProductIDs: @Sendable () async -> Set<String>
    /// Persist / restore the anti-rollback high-water mark. Defaults are in-memory
    /// only for the process; production wires a small Keychain-backed store so a
    /// relaunch after rolling the clock back cannot reopen an ended trial.
    var loadHighWaterMark: @Sendable () -> Date
    var saveHighWaterMark: @Sendable (Date) -> Void

    static var live: PremiumStoreDependencies {
        PremiumStoreDependencies(
            now: { Date() },
            fetchOriginalPurchaseDate: {
                do {
                    let result = try await AppTransaction.shared
                    guard case let .verified(transaction) = result else { return nil }
                    return transaction.originalPurchaseDate
                } catch {
                    Logger.premium.error(
                        "AppTransaction unavailable: \(error.localizedDescription, privacy: .public)"
                    )
                    return nil
                }
            },
            fetchEntitledProductIDs: {
                var owned: Set<String> = []
                for await result in Transaction.currentEntitlements {
                    guard case let .verified(transaction) = result else { continue }
                    if transaction.revocationDate == nil {
                        owned.insert(transaction.productID)
                    }
                }
                return owned
            },
            loadHighWaterMark: { PremiumHighWaterStore.load() },
            saveHighWaterMark: { PremiumHighWaterStore.save($0) }
        )
    }
}

/// Keychain-backed high-water mark for the observed wall clock. Not the trial
/// start date — that always comes from `AppTransaction`. Survives reinstall of
/// UserDefaults but is wiped with the keychain on a full device erase; that is
/// acceptable because App Store still owns the original purchase date.
nonisolated enum PremiumHighWaterStore {
    private static let service = "time.teamplay.premium.highwater"
    private static let account = "maxObservedNow"

    static func load() -> Date {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecUseDataProtectionKeychain as String: true,
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess,
              let data = result as? Data,
              let interval = Double(String(data: data, encoding: .utf8) ?? "")
        else {
            return .distantPast
        }
        return Date(timeIntervalSinceReferenceDate: interval)
    }

    static func save(_ date: Date) {
        let payload = String(date.timeIntervalSinceReferenceDate).data(using: .utf8) ?? Data()
        let baseQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecUseDataProtectionKeychain as String: true,
        ]
        let attributes: [String: Any] = [
            kSecValueData as String: payload,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
        ]
        var status = SecItemUpdate(baseQuery as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var addQuery = baseQuery
            addQuery[kSecValueData as String] = payload
            addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            status = SecItemAdd(addQuery as CFDictionary, nil)
        }
        if status != errSecSuccess {
            Logger.premium.error("Failed to persist premium high-water mark (\(status))")
        }
    }
}

// MARK: - Manager

@MainActor
@Observable
final class PremiumManager {
    static let shared = PremiumManager()

    /// The single product that grants permanent Premium.
    enum Plan: String, CaseIterable {
        case lifetime = "time.teamplay.premium.lifetime"

        /// The plans the paywall may offer.
        static let purchasable: [Plan] = [.lifetime]

        /// No auto-renewables remain on sale.
        var isRenewable: Bool { false }
    }

    /// Loaded `Product`s for the purchasable plans.
    private(set) var products: [Product] = []
    /// Product IDs the user currently owns (lifetime only in the working model).
    private(set) var purchasedProductIDs: Set<String> = []
    /// True while a purchase or restore is in flight.
    private(set) var isWorking = false
    /// Latest resolved access state.
    private(set) var accessState: PremiumAccessState = .loading

    /// Full access when purchased or still inside the trial window.
    var hasFullAccess: Bool {
        #if SIDE_LOAD
            return true
        #elseif DEBUG
            if debugForcePremium { return true }
            return PremiumAccessResolver.hasFullAccess(accessState)
        #else
            return PremiumAccessResolver.hasFullAccess(accessState)
        #endif
    }

    #if SIDE_LOAD
        /// Sideloaded / self-compiled builds unlock everything.
        var isPremium: Bool { true }
    #elseif DEBUG
        /// DEBUG-only override. Defaults to **false** so the free/trial path is
        /// what day-to-day Debug builds exercise; flip on in Settings ▸ Developer
        /// when you need an unlocked sandbox without purchasing.
        static let debugForcePremiumKey = "premium.debugForcePremium"

        var debugForcePremium: Bool = UserDefaults.standard
            .object(forKey: PremiumManager.debugForcePremiumKey) as? Bool ?? false
        {
            didSet { UserDefaults.standard.set(debugForcePremium, forKey: PremiumManager.debugForcePremiumKey) }
        }

        var isPremium: Bool { hasFullAccess }
    #else
        var isPremium: Bool { hasFullAccess }
    #endif

    private var transactionListener: Task<Void, Never>?
    private let dependencies: PremiumStoreDependencies

    private init(dependencies: PremiumStoreDependencies = .live) {
        self.dependencies = dependencies
        #if !SIDE_LOAD
            transactionListener = Task { [weak self] in
                for await update in Transaction.updates {
                    await self?.handle(update)
                }
            }
            Task {
                await loadProducts()
                await refreshEntitlements()
            }
        #else
            accessState = .purchased
        #endif
    }

    /// Test seam: build a manager that never talks to StoreKit.
    init(dependencies: PremiumStoreDependencies, startListener: Bool) {
        self.dependencies = dependencies
        #if SIDE_LOAD
            accessState = .purchased
        #else
            if startListener {
                transactionListener = Task { [weak self] in
                    for await update in Transaction.updates {
                        await self?.handle(update)
                    }
                }
            }
        #endif
    }

    // MARK: - Plan lookup / display

    func product(for plan: Plan) -> Product? {
        products.first { $0.id == plan.rawValue }
    }

    /// Whether the user is currently entitled through that specific plan.
    func owns(_ plan: Plan) -> Bool {
        plan == .lifetime && purchasedProductIDs.contains(Plan.lifetime.rawValue)
    }

    // MARK: - StoreKit

    func loadProducts() async {
        do {
            let ids = Plan.purchasable.map(\.rawValue)
            let loaded = try await Product.products(for: ids)
            products = loaded.sorted { $0.price < $1.price }
            if products.count != ids.count {
                let missing = Set(ids).subtracting(products.map(\.id))
                Logger.premium.error("Missing products (not configured?): \(missing, privacy: .public)")
            }
        } catch {
            Logger.premium.error("Failed to load products: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Purchase a plan. Returns true once the entitlement is granted.
    @discardableResult
    func purchase(_ product: Product) async -> Bool {
        isWorking = true
        defer { isWorking = false }
        do {
            let result = try await purchaseResult(for: product)
            switch result {
            case let .success(verification):
                guard case let .verified(transaction) = verification else {
                    Logger.premium.error("Purchase verification failed for \(product.id, privacy: .public)")
                    return false
                }
                await refreshEntitlements()
                await transaction.finish()
                return hasFullAccess
            case .userCancelled, .pending:
                return false
            @unknown default:
                return false
            }
        } catch {
            Logger.premium.error("Purchase failed: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    private func purchaseResult(for product: Product) async throws -> Product.PurchaseResult {
        #if os(visionOS)
            guard let scene = UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene })
                .first(where: { $0.activationState == .foregroundActive })
                ?? UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first
            else {
                throw PurchaseSceneMissingError()
            }
            return try await product.purchase(confirmIn: scene)
        #else
            return try await product.purchase()
        #endif
    }

    #if os(visionOS)
        private struct PurchaseSceneMissingError: Error {}
    #endif

    /// Restore purchases. Syncs transactions, then re-reads entitlements + trial.
    func restore() async {
        isWorking = true
        defer { isWorking = false }
        try? await AppStore.sync()
        await refreshEntitlements()
    }

    /// Recompute entitlements and trial state from StoreKit / AppTransaction.
    func refreshEntitlements() async {
        #if SIDE_LOAD
            purchasedProductIDs = [Plan.lifetime.rawValue]
            accessState = .purchased
            return
        #else
            let entitled = await dependencies.fetchEntitledProductIDs()
            // Working contract: only the lifetime non-consumable grants purchase.
            let lifetimeOwned = entitled.contains(Plan.lifetime.rawValue)
            purchasedProductIDs = lifetimeOwned ? [Plan.lifetime.rawValue] : []

            let original = await dependencies.fetchOriginalPurchaseDate()
            let rawNow = dependencies.now()
            let previous = dependencies.loadHighWaterMark()
            let highWater = PremiumAccessResolver.advancedHighWater(previous: previous, now: rawNow)
            if highWater != previous {
                dependencies.saveHighWaterMark(highWater)
            }

            accessState = PremiumAccessResolver.resolve(
                PremiumAccessInputs(
                    now: highWater,
                    originalPurchaseDate: original,
                    hasLifetimeEntitlement: lifetimeOwned
                )
            )
        #endif
    }

    /// Re-evaluate with the injected clock without hitting the network. Used by
    /// tests and by any future UI that wants to refresh the trial countdown.
    func reevaluateAccess(
        originalPurchaseDate: Date?,
        hasLifetimeEntitlement: Bool
    ) {
        let rawNow = dependencies.now()
        let previous = dependencies.loadHighWaterMark()
        let highWater = PremiumAccessResolver.advancedHighWater(previous: previous, now: rawNow)
        if highWater != previous {
            dependencies.saveHighWaterMark(highWater)
        }
        purchasedProductIDs = hasLifetimeEntitlement ? [Plan.lifetime.rawValue] : []
        accessState = PremiumAccessResolver.resolve(
            PremiumAccessInputs(
                now: highWater,
                originalPurchaseDate: originalPurchaseDate,
                hasLifetimeEntitlement: hasLifetimeEntitlement
            )
        )
    }

    private func handle(_ result: VerificationResult<Transaction>) async {
        guard case let .verified(transaction) = result else {
            if case let .unverified(transaction, _) = result {
                await transaction.finish()
            }
            return
        }
        await refreshEntitlements()
        await transaction.finish()
    }
}
