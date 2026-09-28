//
//  SettingsView+Premium.swift
//  Lume
//
//  TeamPlay Premium surfaces in Settings: status for trial / purchased / expired /
//  loading, early lifetime purchase during trial, the DEBUG override, and the
//  tvOS Premium pane. Split out of SettingsView to keep that file within the line cap.
//

import StoreKit
import SwiftUI

extension SettingsView {
    /// Sets the highlighted feature and presents the paywall.
    func presentPaywall(_ feature: PremiumFeature? = nil) {
        paywallHighlight = feature
        showPaywall = true
    }

    /// Whether a new playlist can be added (first playlist always free; trial and
    /// lifetime both count as full access).
    var canAddPlaylist: Bool {
        premium.hasFullAccess || playlists.isEmpty
    }

    /// Label for the early-purchase / expired unlock button, preferring the live
    /// StoreKit price when the lifetime product is already loaded.
    var buyForeverButtonTitle: String {
        if let price = premium.product(for: .lifetime)?.displayPrice {
            return PremiumAccessCopy.buyForeverTitle(displayPrice: price)
        }
        return String(localized: "Buy Forever")
    }
}

#if !os(tvOS)

    extension SettingsView {
        /// The first row in Settings: trial / purchased status, a loading
        /// indicator, or a tap-to-upgrade prompt once the trial has ended.
        /// During an active trial the user keeps full access and can still open
        /// the lifetime purchase UI.
        var premiumStatusSection: some View {
            Section {
                switch premium.accessState {
                case .loading:
                    HStack(spacing: 12) {
                        ProgressView()
                            .frame(width: 30)
                        Text(PremiumAccessCopy.statusTitle(for: .loading))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 2)

                case .purchased:
                    HStack(spacing: 12) {
                        Image(systemName: "crown")
                            .foregroundStyle(.tint)
                            .font(.title3)
                            .frame(width: 30)
                        Text(PremiumAccessCopy.statusTitle(for: .purchased))
                    }
                    .padding(.vertical, 2)

                case .trial:
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 12) {
                            Image(systemName: "crown")
                                .foregroundStyle(.tint)
                                .font(.title3)
                                .frame(width: 30)
                            Text(PremiumAccessCopy.statusTitle(for: premium.accessState))
                        }

                        Button {
                            presentPaywall(nil)
                        } label: {
                            Text(buyForeverButtonTitle)
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.regular)
                    }
                    .padding(.vertical, 2)

                case .expired:
                    Button {
                        presentPaywall(nil)
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "crown")
                                .foregroundStyle(.tint)
                                .font(.title3)
                                .frame(width: 30)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(PremiumAccessCopy.statusTitle(for: .expired))
                                    .foregroundStyle(.primary)
                                Text(buyForeverButtonTitle)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                        .padding(.vertical, 2)
                    }
                }
            } header: {
                Text("TeamPlay Premium")
            }
            .task {
                if premium.product(for: .lifetime) == nil {
                    await premium.loadProducts()
                }
            }
        }

        #if DEBUG && !SIDE_LOAD
            /// DEBUG-only override to preview the free tier and the paywall without
            /// archiving a Release build.
            var developerSection: some View {
                Section {
                    Toggle("Force Premium", isOn: Binding(
                        get: { premium.debugForcePremium },
                        set: { premium.debugForcePremium = $0 }
                    ))

                    Button("Recalculate Recommendations") {
                        RecommendationCacheStore().clear(for: ActiveProfileStore.current)
                        recommendationsRecalcToken += 1
                    }
                } header: {
                    Text("Developer")
                } footer: {
                    Text("DEBUG only. Force Premium previews the free tier and paywall. Recalculate rebuilds the For You row now, bypassing the once-a-day throttle.")
                }
            }
        #endif
    }

#endif

#if os(tvOS)

    extension SettingsView {
        /// The tvOS Premium pane: status, benefits, early buy during trial, and
        /// upgrade / restore when expired.
        var tvPremiumDetail: some View {
            VStack(alignment: .leading, spacing: 28) {
                VStack(alignment: .leading, spacing: 8) {
                    TVSettingsSectionLabel("Premium")

                    HStack(spacing: 18) {
                        Group {
                            if case .loading = premium.accessState {
                                ProgressView()
                            } else {
                                Image(systemName: "crown")
                                    .font(.system(size: 28))
                                    .foregroundStyle(.tint)
                            }
                        }
                        .frame(width: 60, height: 60)
                        .background(.tint.opacity(0.12), in: .rect(cornerRadius: 14, style: .continuous))

                        VStack(alignment: .leading, spacing: 2) {
                            Text("TeamPlay Premium")
                                .font(.system(size: 26, weight: .semibold))
                            Text(tvPremiumSubtitle)
                                .font(.system(size: 20))
                                .foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, TVSettingsMetrics.rowHPadding)
                    .padding(.vertical, 8)
                }

                VStack(alignment: .leading, spacing: 16) {
                    TVSettingsSectionLabel(premium.hasFullAccess ? "Included" : "Premium Features")
                    ForEach(PremiumFeature.allCases) { feature in
                        HStack(alignment: .top, spacing: 18) {
                            Image(systemName: feature.systemImage)
                                .font(.system(size: 26))
                                .foregroundStyle(.tint)
                                .frame(width: 40)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(feature.title).font(.system(size: 24, weight: .semibold))
                                Text(feature.subtitle)
                                    .font(.system(size: 20))
                                    .foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, TVSettingsMetrics.rowHPadding)
                    }
                }

                if PremiumPaywallPolicy.allowsLifetimePurchaseUI(for: premium.accessState) {
                    Button {
                        presentPaywall(nil)
                    } label: {
                        HStack(spacing: 16) {
                            Image(systemName: "crown")
                                .font(.system(size: 22, weight: .medium))
                            Text(buyForeverButtonTitle)
                            Spacer(minLength: 0)
                        }
                    }
                    .buttonStyle(TVSettingsRowButtonStyle())

                    Button {
                        Task { await premium.restore() }
                    } label: {
                        HStack(spacing: 16) {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 22, weight: .medium))
                            Text("Restore Purchases")
                            Spacer(minLength: 0)
                        }
                    }
                    .buttonStyle(TVSettingsRowButtonStyle())
                }
            }
            .task {
                if premium.product(for: .lifetime) == nil {
                    await premium.loadProducts()
                }
            }
        }

        private var tvPremiumSubtitle: String {
            PremiumAccessCopy.statusTitle(for: premium.accessState)
        }
    }

#endif
