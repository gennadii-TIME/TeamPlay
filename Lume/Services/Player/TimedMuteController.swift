//
//  TimedMuteController.swift
//  Lume
//
//  Session-scoped timed mute for tvOS. Lives beside the player control
//  session — not tied to any AVPlayerItem, View, or engine instance — so
//  mute survives channel surf, live↔archive, seek reloads, and engine
//  fallback. Only generation-canceled Tasks may unmute.
//

import Combine
import Foundation
import OSLog

/// Timed mute state shared across engine swaps for one playback session.
@MainActor
final class TimedMuteController: ObservableObject {
    /// Preset durations offered in the mute picker (minutes).
    static let presetMinutes: [Int] = [1, 2, 3, 4, 5]

    @Published private(set) var isMuted = false
    /// Wall-clock deadline while a timer is active; `nil` when unmuted or
    /// muted without a timer (manual infinite mute is not offered — every
    /// mute has a duration, cancelled by "Unmute").
    @Published private(set) var endsAt: Date?
    /// Whole seconds remaining for the HUD countdown. `nil` when not muted.
    @Published private(set) var remainingSeconds: Int?

    /// Bumped on every mute/unmute/replace so a superseded Task cannot unmute.
    private(set) var generation = 0
    private var tickTask: Task<Void, Never>?
    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "Lume",
        category: "TimedMute"
    )

    /// Applies mute for `minutes`, cancelling any prior timer. Invokes
    /// `apply(true)` immediately so engines mute before the next frame.
    func mute(forMinutes minutes: Int, apply: @escaping (Bool) -> Void) {
        let clamped = max(1, minutes)
        cancelTickTask()
        generation += 1
        let gen = generation
        let deadline = Date().addingTimeInterval(TimeInterval(clamped * 60))
        isMuted = true
        endsAt = deadline
        remainingSeconds = clamped * 60
        apply(true)
        logger.log("mute minutes=\(clamped, privacy: .public) gen=\(gen, privacy: .public)")
        startTick(generation: gen, apply: apply)
    }

    /// Manual unmute — cancels the active timer.
    func unmute(apply: @escaping (Bool) -> Void) {
        cancelTickTask()
        generation += 1
        isMuted = false
        endsAt = nil
        remainingSeconds = nil
        apply(false)
        logger.log("unmute gen=\(self.generation, privacy: .public)")
    }

    /// Re-assert mute on the current engine after a media/engine swap.
    /// Does not touch the timer or generation.
    func reassert(apply: (Bool) -> Void) {
        apply(isMuted)
    }

    /// Call on scene foreground. If the deadline already passed, unmute now.
    func checkDeadlineOnForeground(apply: @escaping (Bool) -> Void) {
        guard isMuted, let endsAt else { return }
        if Date() >= endsAt {
            unmute(apply: apply)
        } else {
            remainingSeconds = max(0, Int(endsAt.timeIntervalSinceNow.rounded(.down)))
            // Restart tick if the previous Task was cancelled by backgrounding.
            if tickTask == nil {
                startTick(generation: generation, apply: apply)
            }
        }
    }

    /// Test / diagnostics: force the active deadline into the past and run
    /// the foreground check so auto-unmute can be asserted without waiting.
    func expireNowForTesting(apply: @escaping (Bool) -> Void) {
        guard isMuted else { return }
        endsAt = Date().addingTimeInterval(-1)
        remainingSeconds = 0
        checkDeadlineOnForeground(apply: apply)
    }

    /// Remaining time as `MM:SS` for the HUD, or `nil` when not muted.
    var remainingLabel: String? {
        guard isMuted, let remainingSeconds, remainingSeconds >= 0 else { return nil }
        let m = remainingSeconds / 60
        let s = remainingSeconds % 60
        return String(format: "%02d:%02d", m, s)
    }

    // MARK: - Private

    private func startTick(generation gen: Int, apply: @escaping (Bool) -> Void) {
        tickTask = Task { @MainActor in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 250_000_000)
                guard !Task.isCancelled, gen == self.generation else { return }
                guard self.isMuted, let endsAt = self.endsAt else { return }
                let left = endsAt.timeIntervalSinceNow
                if left <= 0 {
                    // Auto-unmute — only if still the owning generation.
                    self.cancelTickTask()
                    self.isMuted = false
                    self.endsAt = nil
                    self.remainingSeconds = nil
                    apply(false)
                    self.logger.log("auto-unmute gen=\(gen, privacy: .public)")
                    return
                }
                self.remainingSeconds = max(0, Int(left.rounded(.down)))
            }
        }
    }

    private func cancelTickTask() {
        tickTask?.cancel()
        tickTask = nil
    }
}
