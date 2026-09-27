//
//  TVChannelSurfInputRouter.swift
//  Lume
//
//  Single gate for live ↑/↓ channel surfing on tvOS. Accepts Apple Remote and
//  HDMI-CEC (Samsung) events, dedupes MoveCommand+UIPress twins, and forwards
//  to SurfCursor when no list/menu owns focus. Compact OSD may stay visible.
//

import Combine
import Foundation

/// Direction for channel surf — mirrors up/down `MoveCommandDirection` without
/// importing SwiftUI (tests run on iOS Simulator).
enum TVChannelSurfDirection: String, Equatable, Sendable {
    case up
    case down
}

/// Where a directional event was observed.
enum TVChannelSurfInputSource: String, Equatable, Sendable {
    case moveCommand
    case uiPress
    case cec
}

/// Snapshot of player chrome the router needs to decide accept/reject.
struct TVChannelSurfGate: Equatable, Sendable {
    /// Informational — compact OSD no longer blocks surf.
    var isOSDVisible: Bool
    /// Channel browser, EPG, info tabs, etc. own ↑/↓.
    var hasOpenPanel: Bool
    /// True only while preview/commit still active; host cancels before evaluate.
    var isScrubbing: Bool
    var allowsChannelSurf: Bool
}

/// Result of evaluating one ↑/↓ input.
struct TVChannelSurfDecision: Equatable, Sendable {
    var accepted: Bool
    var reason: String
}

/// Deduplicating gate in front of `PlayerMediaSwapper.surf` / SurfCursor.
/// Pure decision logic — hosts supply the gate and perform the actual swap.
@MainActor
final class TVChannelSurfInputRouter: ObservableObject {
    /// Same physical press often yields both `onMoveCommand` and `UIPress`
    /// (Apple Remote) or a CEC twin. Collapse those into one surf.
    static let dedupeWindow: TimeInterval = 0.15

    private var lastAccepted: (direction: TVChannelSurfDirection, at: Date)?

    init() {}

    /// Returns whether this event should call the existing channel-surf path.
    @discardableResult
    func evaluate(
        direction: TVChannelSurfDirection,
        source: TVChannelSurfInputSource,
        gate: TVChannelSurfGate,
        phase: String,
        focusTarget: String,
        channelID: String?,
        now: Date = Date()
    ) -> TVChannelSurfDecision {
        let decision: TVChannelSurfDecision
        if gate.hasOpenPanel {
            decision = .init(accepted: false, reason: "panel-open")
        } else if gate.isScrubbing {
            decision = .init(accepted: false, reason: "scrubbing")
        } else if !gate.allowsChannelSurf {
            decision = .init(accepted: false, reason: "session-blocked")
        } else if isDuplicate(direction: direction, at: now) {
            decision = .init(accepted: false, reason: "deduped")
        } else {
            lastAccepted = (direction, now)
            decision = .init(accepted: true, reason: "accepted")
        }

        _ = (gate.isOSDVisible, phase, focusTarget, channelID, source)
        return decision
    }

    /// Clears dedupe state (e.g. after a new stream settles).
    func reset() {
        lastAccepted = nil
    }

    private func isDuplicate(direction: TVChannelSurfDirection, at now: Date) -> Bool {
        guard let last = lastAccepted else { return false }
        guard last.direction == direction else { return false }
        return now.timeIntervalSince(last.at) < Self.dedupeWindow
    }
}
