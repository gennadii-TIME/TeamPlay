//
//  PremiumAccessResolverTests.swift
//  LumeTests
//
//  Pure trial / lifetime resolution: 30 × 24h from the original App Store
//  download, anti-rollback high-water mark, revocation → no access.
//

@testable import Lume
import Foundation
import Testing

struct PremiumAccessResolverTests {
    private let start = Date(timeIntervalSinceReferenceDate: 1_000_000)
    private var trialEnd: Date {
        start.addingTimeInterval(PremiumAccessResolver.trialDuration)
    }

    private func state(
        daysOffset: Double,
        lifetime: Bool = false,
        original: Date? = nil
    ) -> PremiumAccessState {
        let now = start.addingTimeInterval(daysOffset * 24 * 60 * 60)
        return PremiumAccessResolver.resolve(
            PremiumAccessInputs(
                now: now,
                originalPurchaseDate: original ?? start,
                hasLifetimeEntitlement: lifetime
            )
        )
    }

    @Test func `day 0 trial is active`() {
        let resolved = state(daysOffset: 0)
        guard case let .trial(until) = resolved else {
            Issue.record("expected trial, got \(resolved)")
            return
        }
        #expect(until == trialEnd)
        #expect(PremiumAccessResolver.hasFullAccess(resolved))
    }

    @Test func `day 29 trial is still active`() {
        let resolved = state(daysOffset: 29)
        guard case .trial = resolved else {
            Issue.record("expected trial, got \(resolved)")
            return
        }
        #expect(PremiumAccessResolver.hasFullAccess(resolved))
    }

    @Test func `exactly day 30 is expired`() {
        let resolved = state(daysOffset: 30)
        #expect(resolved == .expired)
        #expect(!PremiumAccessResolver.hasFullAccess(resolved))
    }

    @Test func `lifetime purchase is purchased`() {
        let resolved = state(daysOffset: 40, lifetime: true)
        #expect(resolved == .purchased)
        #expect(PremiumAccessResolver.hasFullAccess(resolved))
    }

    @Test func `revoked lifetime does not grant access after trial`() {
        // No entitlement + past trial end → expired (revocation clears the flag).
        let resolved = state(daysOffset: 40, lifetime: false)
        #expect(resolved == .expired)
        #expect(!PremiumAccessResolver.hasFullAccess(resolved))
    }

    @Test func `expired trial without purchase has no access`() {
        let resolved = state(daysOffset: 31, lifetime: false)
        #expect(resolved == .expired)
        #expect(!PremiumAccessResolver.hasFullAccess(resolved))
    }

    @Test func `missing original purchase date expires without lifetime`() {
        let resolved = PremiumAccessResolver.resolve(
            PremiumAccessInputs(
                now: start,
                originalPurchaseDate: nil,
                hasLifetimeEntitlement: false
            )
        )
        #expect(resolved == .expired)
        #expect(!PremiumAccessResolver.hasFullAccess(resolved))
    }

    @Test func `missing original purchase date still honours lifetime`() {
        let resolved = PremiumAccessResolver.resolve(
            PremiumAccessInputs(
                now: start,
                originalPurchaseDate: nil,
                hasLifetimeEntitlement: true
            )
        )
        #expect(resolved == .purchased)
    }

    @Test func `trial duration is exactly thirty times twenty four hours`() {
        #expect(PremiumAccessResolver.trialDuration == 30 * 24 * 60 * 60)
    }

    @Test func `clock rollback high-water does not reopen an ended trial`() {
        let day31 = start.addingTimeInterval(31 * 24 * 60 * 60)
        let day10 = start.addingTimeInterval(10 * 24 * 60 * 60)

        let highWater = PremiumAccessResolver.advancedHighWater(previous: .distantPast, now: day31)
        #expect(highWater == day31)

        // Clock rolled back to day 10, but evaluation still uses the high-water.
        let rolledBackHighWater = PremiumAccessResolver.advancedHighWater(previous: highWater, now: day10)
        #expect(rolledBackHighWater == day31)

        let resolved = PremiumAccessResolver.resolve(
            PremiumAccessInputs(
                now: rolledBackHighWater,
                originalPurchaseDate: start,
                hasLifetimeEntitlement: false
            )
        )
        #expect(resolved == .expired)
        #expect(!PremiumAccessResolver.hasFullAccess(resolved))
    }

    @Test func `clock rollback inside an active trial keeps the later observation`() {
        let day5 = start.addingTimeInterval(5 * 24 * 60 * 60)
        let day2 = start.addingTimeInterval(2 * 24 * 60 * 60)
        let highWater = PremiumAccessResolver.advancedHighWater(
            previous: PremiumAccessResolver.advancedHighWater(previous: .distantPast, now: day5),
            now: day2
        )
        #expect(highWater == day5)

        let resolved = PremiumAccessResolver.resolve(
            PremiumAccessInputs(
                now: highWater,
                originalPurchaseDate: start,
                hasLifetimeEntitlement: false
            )
        )
        guard case .trial = resolved else {
            Issue.record("expected trial, got \(resolved)")
            return
        }
        #expect(PremiumAccessResolver.hasFullAccess(resolved))
    }
}
