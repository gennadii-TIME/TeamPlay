//
//  TVCompactOSDSelectPolicy.swift
//  Lume
//
//  Resolves what one physical Select / OK / CEC click should do for compact
//  live OSD — open chrome, toggle play, or ignore — without ever committing a
//  scrub (auto-commit owns that).
//

import Combine
import Foundation

enum TVCompactOSDSelectAction: String, Equatable, Sendable {
    /// OSD was hidden: reveal chrome only; playback keeps running.
    case openOSDOnly
    /// OSD visible: one Pause/Play toggle (never scrub commit).
    case togglePlay
    /// Commit / seek already owns the pipeline — swallow the click.
    case ignore
}

enum TVCompactOSDSelectPolicy {
    static func resolve(
        osdVisible: Bool,
        isCommitInFlight: Bool,
        isSeekInFlight: Bool
    ) -> TVCompactOSDSelectAction {
        if !osdVisible { return .openOSDOnly }
        if isCommitInFlight || isSeekInFlight { return .ignore }
        return .togglePlay
    }
}

/// Dedupes Apple Select / CEC twins so one physical click toggles play once.
@MainActor
final class TVCompactOSDSelectGate: ObservableObject {
    static let dedupeWindow: TimeInterval = 0.15

    private var lastAcceptedAt: Date?

    func shouldAccept(now: Date = Date()) -> Bool {
        if let last = lastAcceptedAt, now.timeIntervalSince(last) < Self.dedupeWindow {
            return false
        }
        lastAcceptedAt = now
        return true
    }

    func reset() {
        lastAcceptedAt = nil
    }
}
