//
//  PremiumAccessCopyTests.swift
//  LumeTests
//

@testable import Lume
import Foundation
import Testing

struct PremiumAccessCopyTests {
    @Test func `days remaining rounds up within an active trial`() {
        let end = Date(timeIntervalSinceReferenceDate: 1_000_000)
        let almostOneDay = end.addingTimeInterval(-23 * 60 * 60)
        #expect(PremiumAccessCopy.daysRemaining(until: end, now: almostOneDay) == 1)

        let justUnderTwo = end.addingTimeInterval(-(24 * 60 * 60 + 1))
        #expect(PremiumAccessCopy.daysRemaining(until: end, now: justUnderTwo) == 2)
    }

    @Test func `status titles cover every access state`() {
        let end = Date().addingTimeInterval(3 * 24 * 60 * 60)
        #expect(!PremiumAccessCopy.statusTitle(for: .loading).isEmpty)
        #expect(PremiumAccessCopy.statusTitle(for: .purchased) == String(localized: "Full version purchased"))
        #expect(PremiumAccessCopy.statusTitle(for: .expired) == String(localized: "Trial ended"))
        let trial = PremiumAccessCopy.statusTitle(for: .trial(until: end))
        #expect(trial.contains("3") || trial.contains("Trial"))
    }

    @Test func `buy forever title embeds the StoreKit display price`() {
        let title = PremiumAccessCopy.buyForeverTitle(displayPrice: "$9.99")
        #expect(title.contains("9.99"))
    }
}

struct PremiumPaywallPolicyTests {
    private let trialEnd = Date().addingTimeInterval(10 * 24 * 60 * 60)

    @Test func `active trial still has full access`() {
        let state = PremiumAccessState.trial(until: trialEnd)
        #expect(PremiumAccessResolver.hasFullAccess(state))
        #expect(!PremiumPaywallPolicy.shouldAutoDismiss(for: state))
    }

    @Test func `trial can still open the lifetime purchase UI`() {
        let state = PremiumAccessState.trial(until: trialEnd)
        #expect(PremiumPaywallPolicy.allowsLifetimePurchaseUI(for: state))
        #expect(PremiumPaywallPolicy.allowsLifetimePurchaseUI(for: .expired))
        #expect(!PremiumPaywallPolicy.allowsLifetimePurchaseUI(for: .purchased))
        #expect(!PremiumPaywallPolicy.allowsLifetimePurchaseUI(for: .loading))
    }

    @Test func `paywall auto-dismisses only after purchased not merely for active trial`() {
        #expect(PremiumPaywallPolicy.shouldAutoDismiss(for: .purchased))
        #expect(!PremiumPaywallPolicy.shouldAutoDismiss(for: .trial(until: trialEnd)))
        #expect(!PremiumPaywallPolicy.shouldAutoDismiss(for: .expired))
        #expect(!PremiumPaywallPolicy.shouldAutoDismiss(for: .loading))
        // hasFullAccess is true for trial, but that alone must not dismiss.
        #expect(PremiumAccessResolver.hasFullAccess(.trial(until: trialEnd)))
        #expect(!PremiumPaywallPolicy.shouldAutoDismiss(for: .trial(until: trialEnd)))
    }
}
