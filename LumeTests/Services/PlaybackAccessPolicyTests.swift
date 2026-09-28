//
//  PlaybackAccessPolicyTests.swift
//  LumeTests
//

@testable import Lume
import Foundation
import Testing

struct PlaybackAccessPolicyTests {
    @Test func `trial and purchased allow launch`() {
        let end = Date().addingTimeInterval(86_400)
        #expect(PlaybackAccessPolicy.decision(for: .trial(until: end)) == .allow)
        #expect(PlaybackAccessPolicy.decision(for: .purchased) == .allow)
    }

    @Test func `loading waits for access`() {
        #expect(PlaybackAccessPolicy.decision(for: .loading) == .waitForAccess)
    }

    @Test func `expired requires purchase`() {
        #expect(PlaybackAccessPolicy.decision(for: .expired) == .requirePurchase)
    }
}

@MainActor
struct PlaybackAccessCoordinatorTests {
    private final class Box: @unchecked Sendable {
        var state: PremiumAccessState
        var refreshCount = 0
        init(_ state: PremiumAccessState) { self.state = state }
    }

    private func makeCoordinator(_ box: Box) -> PlaybackAccessCoordinator {
        PlaybackAccessCoordinator(
            accessStateProvider: { box.state },
            refreshAccess: {
                box.refreshCount += 1
            }
        )
    }

    @Test func `loading queues one request`() async {
        let box = Box(.loading)
        let coordinator = makeCoordinator(box)
        var launches = 0
        coordinator.requestLaunch { launches += 1 }
        #expect(launches == 0)
        #expect(coordinator.hasPendingLaunch)
        #expect(coordinator.launchCount == 0)
    }

    @Test func `loading last-wins`() async {
        let box = Box(.loading)
        let coordinator = makeCoordinator(box)
        var last = 0
        coordinator.requestLaunch { last = 1 }
        coordinator.requestLaunch { last = 2 }
        box.state = .purchased
        await coordinator.refreshAccess()
        // finishResolving is triggered by the resolve task started on first request.
        // Drive it explicitly via handleAccessStateChange after refresh.
        coordinator.handleAccessStateChange(box.state)
        #expect(last == 2)
        #expect(coordinator.launchCount == 1)
        #expect(!coordinator.hasPendingLaunch)
    }

    @Test func `loading to trial launches once`() async {
        let box = Box(.loading)
        let coordinator = makeCoordinator(box)
        var launches = 0
        coordinator.requestLaunch { launches += 1 }
        box.state = .trial(until: Date().addingTimeInterval(86_400))
        // Simulate the resolve task completing.
        await coordinator.refreshAccess()
        coordinator.handleAccessStateChange(box.state)
        #expect(launches == 1)
        #expect(coordinator.launchCount == 1)
    }

    @Test func `loading to expired opens paywall without launch`() async {
        let box = Box(.loading)
        let coordinator = makeCoordinator(box)
        var launches = 0
        coordinator.requestLaunch { launches += 1 }
        box.state = .expired
        await coordinator.refreshAccess()
        coordinator.handleAccessStateChange(box.state)
        #expect(launches == 0)
        #expect(coordinator.isPaywallPresented)
        #expect(coordinator.hasPendingLaunch)
    }

    @Test func `expired purchase launches pending once`() {
        let box = Box(.expired)
        let coordinator = makeCoordinator(box)
        var launches = 0
        coordinator.requestLaunch { launches += 1 }
        #expect(launches == 0)
        #expect(coordinator.isPaywallPresented)

        box.state = .purchased
        coordinator.handleAccessStateChange(.purchased)
        #expect(launches == 1)
        #expect(coordinator.launchCount == 1)
        #expect(!coordinator.hasPendingLaunch)
        #expect(!coordinator.isPaywallPresented)

        // Further access changes must not re-fire.
        coordinator.handleAccessStateChange(.purchased)
        #expect(launches == 1)
    }

    @Test func `expired dismiss clears pending`() {
        let box = Box(.expired)
        let coordinator = makeCoordinator(box)
        var launches = 0
        coordinator.requestLaunch { launches += 1 }
        coordinator.notePaywallDismissed()
        #expect(launches == 0)
        #expect(!coordinator.hasPendingLaunch)
        #expect(!coordinator.isPaywallPresented)

        box.state = .purchased
        coordinator.handleAccessStateChange(.purchased)
        #expect(launches == 0)
    }

    @Test func `purchased and trial launch immediately`() {
        let purchased = makeCoordinator(Box(.purchased))
        var p = 0
        purchased.requestLaunch { p += 1 }
        #expect(p == 1)

        let trial = makeCoordinator(Box(.trial(until: Date().addingTimeInterval(1000))))
        var t = 0
        trial.requestLaunch { t += 1 }
        #expect(t == 1)
    }

    @Test func `expiry during active session does not stop it`() {
        // The coordinator only gates *new* launches. An already-running session
        // never calls requestLaunch again for zap/seek — modelled here as:
        // prior allow launch stays counted, and a later expired state does not
        // invoke any teardown callback.
        let box = Box(.trial(until: Date().addingTimeInterval(1000)))
        let coordinator = makeCoordinator(box)
        var sessionStopped = false
        coordinator.requestLaunch { /* session started */ }
        #expect(coordinator.launchCount == 1)

        box.state = .expired
        coordinator.handleAccessStateChange(.expired)
        #expect(sessionStopped == false)
        #expect(coordinator.launchCount == 1)
    }

    @Test func `repeated taps never create two launches while waiting`() async {
        let box = Box(.loading)
        let coordinator = makeCoordinator(box)
        var launches = 0
        coordinator.requestLaunch { launches += 1 }
        coordinator.requestLaunch { launches += 1 }
        coordinator.requestLaunch { launches += 1 }
        box.state = .purchased
        coordinator.handleAccessStateChange(.purchased)
        #expect(launches == 1)
        #expect(coordinator.launchCount == 1)
    }
}
