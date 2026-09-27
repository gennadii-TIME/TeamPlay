//
//  TVCompactOSDFocusModel.swift
//  Lume
//
//  Extensible focus graph for the compact live OSD: a timeline zone (scrub) and
//  an actions row (Play/Pause today; Favorite / Mute / Go Live later). Pure
//  value logic so Apple Remote MoveCommand and HDMI-CEC UIPress share one graph
//  and unit tests run on iOS Simulator.
//

import Combine
import Foundation

/// Which compact-OSD zone owns focus.
enum TVCompactOSDFocusZone: String, Equatable, Sendable {
    case timeline
    case actions
}

/// Stable ids for action-row buttons. Add cases as buttons ship — the remote
/// router never switches on these; it only walks `availableActions`.
enum TVCompactOSDActionID: String, Equatable, Sendable, CaseIterable {
    case playPause
    // Future: favorite, mute, goLive, startOver, …
}

/// One slot in the actions row.
struct TVCompactOSDAction: Equatable, Sendable {
    var id: TVCompactOSDActionID
    /// Hidden / disabled actions are skipped by ←/→ and by reconcile.
    var isAvailable: Bool
}

/// Direction for the compact OSD graph (SwiftUI-free for tests).
enum TVCompactOSDMoveDirection: String, Equatable, Sendable {
    case up
    case down
    case left
    case right
}

/// Result of applying one move / reconcile step.
struct TVCompactOSDFocusChange: Equatable, Sendable {
    var didChange: Bool
    var zone: TVCompactOSDFocusZone
    var actionID: TVCompactOSDActionID?
}

/// Extensible compact-OSD focus state.
struct TVCompactOSDFocusModel: Equatable, Sendable {
    var zone: TVCompactOSDFocusZone
    /// Index into `availableActions` while `zone == .actions`.
    var actionIndex: Int
    var actions: [TVCompactOSDAction]
    /// When false, ↑ from actions is a no-op and the model never parks on the
    /// timeline. Compact live always keeps the timeline focusable for Select.
    var timelineAvailable: Bool

    /// Available action buttons in row order.
    var availableActions: [TVCompactOSDAction] {
        actions.filter(\.isAvailable)
    }

    /// Focused action id when in the actions zone.
    var focusedActionID: TVCompactOSDActionID? {
        guard zone == .actions else { return nil }
        let available = availableActions
        guard available.indices.contains(actionIndex) else { return available.first?.id }
        return available[actionIndex].id
    }

    /// Default landing when the OSD opens: timeline when available, else the
    /// first action. Today's compact OSD ships an empty action row.
    static func initial(timelineAvailable: Bool, actions: [TVCompactOSDAction]) -> TVCompactOSDFocusModel {
        var model = TVCompactOSDFocusModel(
            zone: timelineAvailable ? .timeline : .actions,
            actionIndex: 0,
            actions: actions,
            timelineAvailable: timelineAvailable
        )
        _ = model.reconcile()
        return model
    }

    /// Shipped action row is empty — Play/Pause lives on timeline Select.
    /// Keep the API so future Favorite / Mute / Go Live can append here.
    static func standardActions(playPauseAvailable: Bool = false) -> [TVCompactOSDAction] {
        _ = playPauseAvailable
        return []
    }

    /// Apply ↑/↓/←/→ inside the compact OSD. Timeline ←/→ are not focus moves
    /// (scrub owns those); they return `didChange: false` so the host can scrub.
    @discardableResult
    mutating func move(_ direction: TVCompactOSDMoveDirection) -> TVCompactOSDFocusChange {
        switch (zone, direction) {
        case (.timeline, .down):
            let available = availableActions
            guard !available.isEmpty else { return snapshot(changed: false) }
            zone = .actions
            actionIndex = 0
            return snapshot(changed: true)

        case (.timeline, .up), (.timeline, .left), (.timeline, .right):
            return snapshot(changed: false)

        case (.actions, .up):
            guard timelineAvailable else { return snapshot(changed: false) }
            zone = .timeline
            return snapshot(changed: true)

        case (.actions, .down):
            return snapshot(changed: false)

        case (.actions, .left):
            return moveAction(by: -1)

        case (.actions, .right):
            return moveAction(by: 1)
        }
    }

    /// After the available-action set changes (button added/removed/disabled),
    /// keep focus on the same id when possible; otherwise land on the nearest
    /// remaining action or fall back to the timeline.
    @discardableResult
    mutating func reconcile() -> TVCompactOSDFocusChange {
        let before = snapshot(changed: false)
        let available = availableActions

        if !timelineAvailable, zone == .timeline {
            if available.isEmpty {
                zone = .actions
                actionIndex = 0
            } else {
                zone = .actions
                actionIndex = min(actionIndex, available.count - 1)
            }
        }

        guard zone == .actions else {
            return snapshot(changed: before.zone != zone || before.actionID != focusedActionID)
        }

        if available.isEmpty {
            if timelineAvailable {
                zone = .timeline
                actionIndex = 0
            } else {
                actionIndex = 0
            }
            return snapshot(changed: true)
        }

        if let id = before.actionID, let idx = available.firstIndex(where: { $0.id == id }) {
            actionIndex = idx
        } else {
            actionIndex = min(max(actionIndex, 0), available.count - 1)
        }
        return snapshot(changed: before.zone != zone || before.actionID != focusedActionID)
    }

    /// Play ↔ Pause (or any in-place state flip) must not move focus: the action
    /// id is unchanged, so reconcile is a no-op when availability is stable.
    @discardableResult
    mutating func noteActionPresentationChanged() -> TVCompactOSDFocusChange {
        reconcile()
    }

    private mutating func moveAction(by delta: Int) -> TVCompactOSDFocusChange {
        let available = availableActions
        guard available.count > 1 else { return snapshot(changed: false) }
        let next = actionIndex + delta
        guard available.indices.contains(next) else { return snapshot(changed: false) }
        actionIndex = next
        return snapshot(changed: true)
    }

    private func snapshot(changed: Bool) -> TVCompactOSDFocusChange {
        TVCompactOSDFocusChange(didChange: changed, zone: zone, actionID: focusedActionID)
    }
}

/// Dedupes MoveCommand + CEC/UIPress twins so one physical click moves focus once.
@MainActor
final class TVCompactOSDFocusInputGate: ObservableObject {
    static let dedupeWindow: TimeInterval = 0.15

    private var lastAccepted: (direction: TVCompactOSDMoveDirection, at: Date)?

    func shouldAccept(_ direction: TVCompactOSDMoveDirection, now: Date = Date()) -> Bool {
        if let last = lastAccepted,
           last.direction == direction,
           now.timeIntervalSince(last.at) < Self.dedupeWindow
        {
            return false
        }
        lastAccepted = (direction, now)
        return true
    }

    func reset() {
        lastAccepted = nil
    }
}
