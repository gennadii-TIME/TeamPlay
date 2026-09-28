//
//  PaywallView.swift
//  Lume
//
//  TeamPlay Premium paywall: 30-day free trial framing + a single lifetime
//  non-consumable. No subscriptions, no auto-renewal copy. Presented as a sheet
//  when a gated feature is hit or from Settings. Never shown in sideloaded builds.
//

import OSLog
import StoreKit
import SwiftUI

struct PaywallView: View {
    /// The feature that triggered the paywall, highlighted at the top. Nil when
    /// opened from the Settings status row (a general upgrade prompt).
    var highlight: PremiumFeature?

    @State private var premium = PremiumManager.shared
    @State private var lifetimeProduct: Product?
    @State private var isLoadingProducts = true
    @State private var productsFailed = false
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    #if !os(tvOS)
        /// Offer-code redemption (iOS / macOS). tvOS redeems in the App Store app.
        @State private var showRedeemCode = false
    #endif

    private static let termsURL = URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!
    private static let privacyURL = URL(string: "https://github.com/gennadii-TIME/TeamPlay/blob/main/docs/RELEASE_COMPLIANCE.md")!

    var body: some View {
        #if os(tvOS)
            tvBody
                .task { await reloadProducts() }
                .onChange(of: premium.accessState) { _, state in
                    if PremiumPaywallPolicy.shouldAutoDismiss(for: state) {
                        dismiss()
                    }
                }
        #else
            standardBody
                .task { await reloadProducts() }
                .onChange(of: premium.accessState) { _, state in
                    if PremiumPaywallPolicy.shouldAutoDismiss(for: state) {
                        dismiss()
                    }
                }
        #endif
    }

    private var orderedFeatures: [PremiumFeature] {
        guard let highlight else { return PremiumFeature.allCases }
        return [highlight] + PremiumFeature.allCases.filter { $0 != highlight }
    }

    private func reloadProducts() async {
        isLoadingProducts = true
        productsFailed = false
        await premium.loadProducts()
        lifetimeProduct = premium.product(for: .lifetime)
        productsFailed = lifetimeProduct == nil
        isLoadingProducts = false
    }

    /// Purchase via PremiumManager. Cancelled / pending / failed results return
    /// false and leave entitlements unchanged — the paywall stays up and access
    /// is not granted.
    private func buy(_ product: Product) async {
        _ = await premium.purchase(product)
    }

    // MARK: - iOS / macOS

    #if !os(tvOS)
        private var standardBody: some View {
            NavigationStack {
                ScrollView {
                    VStack(spacing: 28) {
                        header
                        benefitsList
                        purchaseSection
                        redeemButton
                        legalFooter
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 24)
                    .frame(maxWidth: 520)
                    .frame(maxWidth: .infinity)
                }
                .navigationTitle("TeamPlay Premium")
                #if os(iOS)
                    .navigationBarTitleDisplayMode(.inline)
                #endif
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Close") { dismiss() }
                        }
                        ToolbarItem(placement: .primaryAction) {
                            Button("Restore Purchases") {
                                Task { await premium.restore() }
                            }
                            .disabled(premium.isWorking)
                        }
                    }
                    .offerCodeRedemption(isPresented: $showRedeemCode) { result in
                        if case let .failure(error) = result {
                            Logger.premium.error(
                                "Offer code redemption failed: \(error.localizedDescription, privacy: .public)"
                            )
                        }
                        Task { await premium.refreshEntitlements() }
                    }
            }
            #if os(macOS)
            .frame(minWidth: 460, idealWidth: 520, minHeight: 560, idealHeight: 680)
            #endif
        }

        private var redeemButton: some View {
            Button("Redeem Code") { showRedeemCode = true }
                .font(.callout.weight(.medium))
                .buttonStyle(.plain)
                .foregroundStyle(.tint)
                .disabled(premium.isWorking)
        }

        private var header: some View {
            VStack(spacing: 10) {
                Image(systemName: "crown")
                    .font(.system(size: 44))
                    .foregroundStyle(.tint)
                Text("TeamPlay Premium")
                    .font(.title.bold())
                    .multilineTextAlignment(.center)
                Text(paywallHeadline)
                    .font(.title3.weight(.semibold))
                    .multilineTextAlignment(.center)
                Text("One-time purchase. No subscription and no automatic billing.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }

        private var benefitsList: some View {
            VStack(spacing: 16) {
                ForEach(orderedFeatures) { feature in
                    HStack(alignment: .top, spacing: 14) {
                        Image(systemName: feature.systemImage)
                            .font(.title3)
                            .foregroundStyle(.tint)
                            .frame(width: 30)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(feature.title).font(.headline)
                            Text(feature.subtitle)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 0)
                    }
                }
            }
        }

        @ViewBuilder
        private var purchaseSection: some View {
            VStack(spacing: 12) {
                if isLoadingProducts {
                    ProgressView()
                        .padding(.vertical, 12)
                } else if productsFailed || lifetimeProduct == nil {
                    Text("Couldn’t load the price. Check your connection and try again.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    Button("Try Again") {
                        Task { await reloadProducts() }
                    }
                    .buttonStyle(.bordered)
                } else if let product = lifetimeProduct {
                    Button {
                        Task { await buy(product) }
                    } label: {
                        if premium.isWorking {
                            ProgressView()
                                .frame(maxWidth: .infinity)
                        } else {
                            Text(PremiumAccessCopy.buyForeverTitle(displayPrice: product.displayPrice))
                                .fontWeight(.semibold)
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(premium.isWorking)
                }
            }
        }

        private var legalFooter: some View {
            VStack(spacing: 8) {
                Text("Payment is charged to your Apple Account. This is a one-time purchase — nothing renews and there is nothing to cancel.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                HStack(spacing: 16) {
                    Button("Terms of Use") { openURL(Self.termsURL) }
                    Button("Privacy Policy") { openURL(Self.privacyURL) }
                }
                .font(.caption2)
                .buttonStyle(.plain)
                .foregroundStyle(.tint)
            }
        }
    #endif

    // MARK: - tvOS

    #if os(tvOS)
        private var tvBody: some View {
            ScrollView {
                HStack(alignment: .top, spacing: 60) {
                    VStack(alignment: .leading, spacing: 18) {
                        Image(systemName: "crown")
                            .font(.system(size: 56))
                            .foregroundStyle(.tint)
                        Text("TeamPlay Premium")
                            .font(.system(size: 48, weight: .bold))
                        Text(paywallHeadline)
                            .font(.system(size: 32, weight: .semibold))
                        Text("One-time purchase. No subscription and no automatic billing.")
                            .font(.system(size: 24))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: 560, alignment: .leading)

                        VStack(alignment: .leading, spacing: 18) {
                            ForEach(orderedFeatures) { feature in
                                HStack(alignment: .top, spacing: 18) {
                                    Image(systemName: feature.systemImage)
                                        .font(.system(size: 28))
                                        .foregroundStyle(.tint)
                                        .frame(width: 44)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(feature.title).font(.system(size: 26, weight: .semibold))
                                        Text(feature.subtitle)
                                            .font(.system(size: 22))
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                        .padding(.top, 12)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    VStack(spacing: 20) {
                        tvPurchaseSection

                        Button("Restore Purchases") {
                            Task { await premium.restore() }
                        }
                        .disabled(premium.isWorking)

                        Button("Not Now") { dismiss() }
                    }
                    .frame(width: 460)
                }
                .padding(80)
            }
        }

        @ViewBuilder
        private var tvPurchaseSection: some View {
            if isLoadingProducts {
                ProgressView()
            } else if productsFailed || lifetimeProduct == nil {
                Text("Couldn’t load the price. Check your connection and try again.")
                    .font(.system(size: 22))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Button("Try Again") {
                    Task { await reloadProducts() }
                }
            } else if let product = lifetimeProduct {
                Button {
                    Task { await buy(product) }
                } label: {
                    Group {
                        if premium.isWorking {
                            ProgressView()
                        } else {
                            Text(PremiumAccessCopy.buyForeverTitle(displayPrice: product.displayPrice))
                                .font(.system(size: 26, weight: .semibold))
                                .multilineTextAlignment(.center)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                }
                .disabled(premium.isWorking)
            }
        }
    #endif

    /// Headline under the title: remaining trial days when still in trial,
    /// otherwise the generic free-period line for expired / loading.
    private var paywallHeadline: String {
        if case .trial = premium.accessState {
            return PremiumAccessCopy.statusTitle(for: premium.accessState)
        }
        if case .expired = premium.accessState {
            return PremiumAccessCopy.statusTitle(for: .expired)
        }
        return String(localized: "30 days free")
    }
}

// MARK: - Paywall presentation policy

/// Pure rules for when the paywall may stay open during trial and when it must
/// dismiss after a successful lifetime unlock.
enum PremiumPaywallPolicy {
    /// Auto-dismiss only after a verified lifetime purchase — never merely
    /// because the user still has an active trial (`hasFullAccess` alone).
    static func shouldAutoDismiss(for state: PremiumAccessState) -> Bool {
        if case .purchased = state { return true }
        return false
    }

    /// Trial and expired users can open the lifetime purchase UI. Purchased
    /// users have nothing left to buy; loading has no resolved offer yet.
    static func allowsLifetimePurchaseUI(for state: PremiumAccessState) -> Bool {
        switch state {
        case .trial, .expired:
            return true
        case .loading, .purchased:
            return false
        }
    }
}

// MARK: - Shared status copy (Settings + tvOS shell)

enum PremiumAccessCopy {
    /// Days left in an active trial, always ≥ 1 while the trial state is active.
    static func daysRemaining(until end: Date, now: Date = Date()) -> Int {
        let seconds = end.timeIntervalSince(now)
        guard seconds > 0 else { return 0 }
        return max(1, Int((seconds / (24 * 60 * 60)).rounded(.up)))
    }

    static func statusTitle(for state: PremiumAccessState, now: Date = Date()) -> String {
        switch state {
        case .loading:
            return String(localized: "Checking access…")
        case let .trial(until):
            let days = daysRemaining(until: until, now: now)
            return String(localized: "Trial — \(days) days left")
        case .purchased:
            return String(localized: "Full version purchased")
        case .expired:
            return String(localized: "Trial ended")
        }
    }

    static func buyForeverTitle(displayPrice: String) -> String {
        String(localized: "Buy Forever — \(displayPrice)")
    }
}
