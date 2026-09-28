//
//  PlaybackAccessCoordinator.swift
//  Lume
//
//  Single gate for starting a new playback session after the free trial.
//  Call sites hand a launch closure here; the coordinator either runs it,
//  queues it while Premium is still loading, or holds it behind the lifetime
//  paywall until purchase / restore. In-player navigation never goes through
//  this type.
//

import Foundation
import SwiftUI

@MainActor
@Observable
final class PlaybackAccessCoordinator {
    static let shared = PlaybackAccessCoordinator()

    /// Drives the shared lifetime paywall sheet on root hosts.
    private(set) var isPaywallPresented = false

    /// Test / injection seam for the Premium access state.
    var accessStateProvider: () -> PremiumAccessState = { PremiumManager.shared.accessState }

    /// Test / injection seam that resolves `.loading` (defaults to a real refresh).
    var refreshAccess: () async -> Void = { await PremiumManager.shared.refreshEntitlements() }

    /// Number of times a launch closure has been executed (unit tests).
    private(set) var launchCount = 0

    /// Last-wins pending work while loading or waiting on purchase.
    private var pendingLaunch: (@MainActor () -> Void)?

    /// In-flight resolution of `.loading` — coalesces rapid taps.
    private var resolveTask: Task<Void, Never>?

    private init() {}

    /// Test seam: empty coordinator with injectable state.
    init(accessStateProvider: @escaping () -> PremiumAccessState,
         refreshAccess: @escaping () async -> Void)
    {
        self.accessStateProvider = accessStateProvider
        self.refreshAccess = refreshAccess
    }

    // MARK: - Public API

    /// Request a new playback session. `perform` must create the player /
    /// hand off to an external player — it is invoked at most once per
    /// accepted request (last-wins replaces any previous pending work).
    func requestLaunch(perform: @escaping @MainActor () -> Void) {
        switch PlaybackAccessPolicy.decision(for: accessStateProvider()) {
        case .allow:
            // Drop any stale pending from an earlier loading/expired attempt.
            pendingLaunch = nil
            executeLaunch(perform)
        case .requirePurchase:
            pendingLaunch = perform
            isPaywallPresented = true
        case .waitForAccess:
            pendingLaunch = perform
            startResolvingIfNeeded()
        }
    }

    /// Roots bind the paywall with this so dismiss / purchase stay in sync.
    var paywallPresented: Binding<Bool> {
        Binding(
            get: { self.isPaywallPresented },
            set: { newValue in
                if newValue {
                    self.isPaywallPresented = true
                } else {
                    self.notePaywallDismissed()
                }
            }
        )
    }

    /// Call whenever `PremiumManager.accessState` changes (purchase, restore,
    /// refresh). Launches a pending request once access becomes allowed.
    func handleAccessStateChange(_ state: PremiumAccessState) {
        switch PlaybackAccessPolicy.decision(for: state) {
        case .allow:
            isPaywallPresented = false
            consumePendingLaunch()
        case .requirePurchase:
            // Keep pending; ensure the paywall is visible if we already queued.
            if pendingLaunch != nil {
                isPaywallPresented = true
            }
        case .waitForAccess:
            if pendingLaunch != nil {
                startResolvingIfNeeded()
            }
        }
    }

    /// Paywall closed without a successful purchase — drop the pending launch.
    func notePaywallDismissed() {
        isPaywallPresented = false
        if PlaybackAccessPolicy.decision(for: accessStateProvider()) != .allow {
            pendingLaunch = nil
        } else {
            // Dismiss raced with purchase — still honour a pending launch once.
            consumePendingLaunch()
        }
    }

    /// DEBUG / SIDE_LOAD screenshot helpers may bypass the gate.
    static var allowsScreenshotBypass: Bool {
        #if SIDE_LOAD || DEBUG
            true
        #else
            false
        #endif
    }

    // MARK: - Internals

    private func executeLaunch(_ perform: @escaping @MainActor () -> Void) {
        launchCount += 1
        perform()
    }

    private func consumePendingLaunch() {
        guard let work = pendingLaunch else { return }
        pendingLaunch = nil
        executeLaunch(work)
    }

    private func startResolvingIfNeeded() {
        guard resolveTask == nil else { return }
        resolveTask = Task { [weak self] in
            await self?.refreshAccess()
            self?.resolveTask = nil
            self?.finishResolving()
        }
    }

    private func finishResolving() {
        guard pendingLaunch != nil else { return }
        switch PlaybackAccessPolicy.decision(for: accessStateProvider()) {
        case .allow:
            isPaywallPresented = false
            consumePendingLaunch()
        case .requirePurchase:
            isPaywallPresented = true
        case .waitForAccess:
            // Still unresolved after a refresh — treat as purchase required so
            // the user is never stuck on a silent no-op.
            isPaywallPresented = true
        }
    }

    /// Whether a launch is waiting on loading / purchase (tests + diagnostics).
    var hasPendingLaunch: Bool { pendingLaunch != nil }

    /// Unit-test helper to clear coordinator state between cases.
    func resetForTests() {
        pendingLaunch = nil
        isPaywallPresented = false
        launchCount = 0
        resolveTask?.cancel()
        resolveTask = nil
    }
}
