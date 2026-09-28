//
//  PlaybackAccessPolicy.swift
//  Lume
//
//  Pure decision for whether a *new* playback session may start. In-player
//  swaps (channel zap, next episode, archive ↔ live, seek) never consult this.
//

import Foundation

nonisolated enum PlaybackAccessPolicy {
    /// Outcome for a launch request against the current Premium access state.
    enum Decision: Equatable, Sendable {
        /// Start playback immediately (trial or purchased).
        case allow
        /// Access is still resolving — queue the request and wait.
        case waitForAccess
        /// Trial ended — show the lifetime paywall; do not create a player.
        case requirePurchase
    }

    static func decision(for state: PremiumAccessState) -> Decision {
        switch state {
        case .loading:
            return .waitForAccess
        case .trial, .purchased:
            return .allow
        case .expired:
            return .requirePurchase
        }
    }
}
