//
//  PremiumManagerAccessTests.swift
//  LumeTests
//
//  Exercises PremiumManager against an injected clock / entitlement source so
//  trial → purchase → revoke transitions do not need a StoreKit sandbox.
//

@testable import Lume
import Foundation
import Testing

@MainActor
struct PremiumManagerAccessTests {
    private let start = Date(timeIntervalSinceReferenceDate: 2_000_000)

    private final class Box: @unchecked Sendable {
        var now: Date
        var original: Date?
        var entitled: Set<String>
        var highWater: Date

        init(now: Date, original: Date?, entitled: Set<String>, highWater: Date) {
            self.now = now
            self.original = original
            self.entitled = entitled
            self.highWater = highWater
        }
    }

    private func makeManager(box: Box) -> PremiumManager {
        #if DEBUG
            UserDefaults.standard.set(false, forKey: PremiumManager.debugForcePremiumKey)
        #endif
        let dependencies = PremiumStoreDependencies(
            now: { box.now },
            fetchOriginalPurchaseDate: { box.original },
            fetchEntitledProductIDs: { box.entitled },
            loadHighWaterMark: { box.highWater },
            saveHighWaterMark: { box.highWater = $0 }
        )
        return PremiumManager(dependencies: dependencies, startListener: false)
    }

    @Test func `manager reports trial on day 0`() async {
        let box = Box(now: start, original: start, entitled: [], highWater: .distantPast)
        let manager = makeManager(box: box)
        await manager.refreshEntitlements()

        guard case let .trial(until) = manager.accessState else {
            Issue.record("expected trial, got \(manager.accessState)")
            return
        }
        #expect(until == start.addingTimeInterval(PremiumAccessResolver.trialDuration))
        #expect(manager.hasFullAccess)
        #expect(manager.isPremium == manager.hasFullAccess)
        #expect(manager.purchasedProductIDs.isEmpty)
    }

    @Test func `manager reports purchased when lifetime entitled`() async {
        let box = Box(
            now: start.addingTimeInterval(40 * 24 * 60 * 60),
            original: start,
            entitled: [PremiumManager.Plan.lifetime.rawValue],
            highWater: .distantPast
        )
        let manager = makeManager(box: box)
        await manager.refreshEntitlements()

        #expect(manager.accessState == .purchased)
        #expect(manager.hasFullAccess)
        #expect(manager.owns(.lifetime))
        #expect(manager.purchasedProductIDs == [PremiumManager.Plan.lifetime.rawValue])
    }

    @Test func `revoked or missing lifetime after trial expires access`() async {
        let box = Box(
            now: start.addingTimeInterval(40 * 24 * 60 * 60),
            original: start,
            entitled: [],
            highWater: .distantPast
        )
        let manager = makeManager(box: box)
        await manager.refreshEntitlements()

        #expect(manager.accessState == .expired)
        #expect(!manager.hasFullAccess)
        #expect(!manager.owns(.lifetime))
    }

    @Test func `legacy monthly ids in the receipt do not grant access`() async {
        let box = Box(
            now: start.addingTimeInterval(40 * 24 * 60 * 60),
            original: start,
            entitled: [
                "time.teamplay.premium.monthly",
                "time.teamplay.premium.monthly.retired",
                "com.bilipp.lume.premium.lifetime",
            ],
            highWater: .distantPast
        )
        let manager = makeManager(box: box)
        await manager.refreshEntitlements()

        #expect(manager.accessState == .expired)
        #expect(!manager.hasFullAccess)
        #expect(manager.purchasedProductIDs.isEmpty)
        #expect(!manager.hasManageableSubscription)
        #expect(manager.subscriptionStatus == nil)
    }

    @Test func `clock rollback after expiry does not restore trial`() async {
        let day31 = start.addingTimeInterval(31 * 24 * 60 * 60)
        let day5 = start.addingTimeInterval(5 * 24 * 60 * 60)
        let box = Box(now: day31, original: start, entitled: [], highWater: .distantPast)
        let manager = makeManager(box: box)

        await manager.refreshEntitlements()
        #expect(manager.accessState == .expired)
        #expect(box.highWater == day31)

        box.now = day5
        await manager.refreshEntitlements()
        #expect(manager.accessState == .expired)
        #expect(!manager.hasFullAccess)
        #expect(box.highWater == day31)
    }

    #if SIDE_LOAD
        @Test func `sideload build always reports full access`() async {
            let box = Box(
                now: start.addingTimeInterval(100 * 24 * 60 * 60),
                original: nil,
                entitled: [],
                highWater: .distantPast
            )
            let manager = makeManager(box: box)
            await manager.refreshEntitlements()
            #expect(manager.hasFullAccess)
            #expect(manager.isPremium)
            #expect(manager.accessState == .purchased)
        }
    #else
        @Test func `non sideload build denies access without trial or purchase`() async {
            let box = Box(
                now: start.addingTimeInterval(100 * 24 * 60 * 60),
                original: nil,
                entitled: [],
                highWater: .distantPast
            )
            let manager = makeManager(box: box)
            await manager.refreshEntitlements()
            #expect(!manager.hasFullAccess)
            #expect(manager.accessState == .expired)
        }
    #endif
}
