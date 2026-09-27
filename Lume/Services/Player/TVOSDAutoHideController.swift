//
//  TVOSDAutoHideController.swift
//  Lume
//
//  Deterministic compact-OSD auto-hide deadline. Playback clock / EPG / scrubber
//  text updates never touch this — only explicit user interaction or a scrub/
//  seek settle restarts the timer.
//

import Foundation

/// Pure deadline math so unit tests can drive time without sleeping.
enum TVOSDAutoHidePolicy: Sendable {
    enum Event: Sendable {
        case userInteraction
        case playbackClockTick
        case epgOrChromeTextUpdate
        case scrubOrSeekActive
        case scrubOrSeekSettled
        case panelOpened
        case panelClosed
    }

    /// Whether `event` may replace the current hide deadline.
    static func shouldRestartDeadline(for event: Event) -> Bool {
        switch event {
        case .userInteraction, .scrubOrSeekSettled, .panelClosed:
            return true
        case .playbackClockTick, .epgOrChromeTextUpdate, .scrubOrSeekActive, .panelOpened:
            return false
        }
    }

    /// Absolute deadline after `delay` from `now`.
    static func deadline(from now: Date, delay: TimeInterval) -> Date {
        now.addingTimeInterval(max(0, delay))
    }

    /// Hide when the deadline has elapsed and hide is not blocked (scrub/seek/panel).
    static func shouldHide(now: Date, deadline: Date?, isBlocked: Bool) -> Bool {
        guard !isBlocked, let deadline else { return false }
        return now >= deadline
    }

    /// Compact OSD may auto-hide only while chrome is up and no panel/scrub/seek
    /// is pinning it. Playback paused/playing must not gate the timer.
    static func isHideBlocked(
        isControlsVisible: Bool,
        isPanelOpen: Bool,
        isScrubbing: Bool,
        isSeekInFlight: Bool
    ) -> Bool {
        !isControlsVisible || isPanelOpen || isScrubbing || isSeekInFlight
    }
}

/// Session-scoped auto-hide timer for the tvOS player chrome.
@MainActor
final class TVOSDAutoHideController {
    private(set) var deadline: Date?
    private var task: Task<Void, Never>?
    private let delayProvider: () -> TimeInterval
    private let nowProvider: () -> Date
    private let isBlocked: () -> Bool
    private let onHide: () -> Void

    init(
        delayProvider: @escaping () -> TimeInterval = { PlayerSettings.OSD.hideDelayInterval },
        nowProvider: @escaping () -> Date = { Date() },
        isBlocked: @escaping () -> Bool,
        onHide: @escaping () -> Void
    ) {
        self.delayProvider = delayProvider
        self.nowProvider = nowProvider
        self.isBlocked = isBlocked
        self.onHide = onHide
    }

    /// User gesture or post-scrub settle — cancel and arm a full delay.
    func noteUserInteraction() {
        guard TVOSDAutoHidePolicy.shouldRestartDeadline(for: .userInteraction) else { return }
        schedule(from: nowProvider())
    }

    /// Scrub/seek finished — start a fresh full timer if chrome is still up.
    func noteScrubOrSeekSettled() {
        guard TVOSDAutoHidePolicy.shouldRestartDeadline(for: .scrubOrSeekSettled) else { return }
        schedule(from: nowProvider())
    }

    /// Panel/tab opened — pin chrome (no hide while blocked).
    func notePanelOpened() {
        cancel()
    }

    /// Panel/tab closed — resume auto-hide.
    func notePanelClosed() {
        schedule(from: nowProvider())
    }

    /// Playback / EPG / progress ticks must never restart the deadline.
    func notePlaybackClockTick() {
        _ = TVOSDAutoHidePolicy.shouldRestartDeadline(for: .playbackClockTick)
    }

    func cancel() {
        task?.cancel()
        task = nil
        deadline = nil
    }

    func schedule(from now: Date? = nil) {
        let instant = now ?? nowProvider()
        task?.cancel()
        guard !isBlocked() else {
            deadline = nil
            task = nil
            return
        }
        let delay = delayProvider()
        let fireAt = TVOSDAutoHidePolicy.deadline(from: instant, delay: delay)
        deadline = fireAt
        task = Task { @MainActor in
            let remaining = fireAt.timeIntervalSince(nowProvider())
            if remaining > 0 {
                try? await Task.sleep(nanoseconds: UInt64(remaining * 1_000_000_000))
            }
            guard !Task.isCancelled else { return }
            guard TVOSDAutoHidePolicy.shouldHide(
                now: nowProvider(),
                deadline: deadline,
                isBlocked: isBlocked()
            ) else { return }
            deadline = nil
            task = nil
            onHide()
        }
    }
}
