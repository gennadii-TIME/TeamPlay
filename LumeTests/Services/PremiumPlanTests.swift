//
//  PremiumPlanTests.swift
//  LumeTests
//
//  Contract tests for the TeamPlay Premium catalogue: a single lifetime
//  non-consumable, no subscriptions, no legacy bilipp / monthly IDs on sale.
//

@testable import Lume
import Testing

@MainActor
struct PremiumPlanTests {
    @Test func `product id is the TeamPlay lifetime unlock`() {
        #expect(PremiumManager.Plan.lifetime.rawValue == "time.teamplay.premium.lifetime")
    }

    @Test func `only lifetime is purchasable`() {
        #expect(PremiumManager.Plan.purchasable == [.lifetime])
        #expect(PremiumManager.Plan.allCases == [.lifetime])
    }

    @Test func `nothing is renewable`() {
        #expect(PremiumManager.Plan.allCases.filter(\.isRenewable).isEmpty)
        #expect(!PremiumManager.Plan.lifetime.isRenewable)
    }

    @Test func `legacy bilipp and monthly ids are not in the working contract`() {
        let ids = Set(PremiumManager.Plan.allCases.map(\.rawValue))
        #expect(ids == ["time.teamplay.premium.lifetime"])
        #expect(!ids.contains("time.teamplay.premium.monthly"))
        #expect(!ids.contains("time.teamplay.premium.monthly.retired"))
        #expect(!ids.contains("com.bilipp.lume.pro.monthly"))
        #expect(!ids.contains("com.bilipp.lume.premium.lifetime"))
        #expect(!ids.contains("com.bilipp.lume.premium.monthly"))
    }
}
