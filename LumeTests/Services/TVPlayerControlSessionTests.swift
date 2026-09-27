//
//  TVPlayerControlSessionTests.swift
//  LumeTests
//
//  Exercises the exclusive tvOS control-phase machine with remote-like
//  event sequences and asserts media-reload counts (no live network).
//

import XCTest
@testable import Lume

@MainActor
final class TVPlayerControlSessionTests: XCTestCase {
    func testPhaseGraphAllowsExpectedEdgesOnly() {
        XCTAssertTrue(TVPlayerControlSession.isAllowed(from: .live, to: .controls))
        XCTAssertTrue(TVPlayerControlSession.isAllowed(from: .controls, to: .scrubPreview))
        XCTAssertTrue(TVPlayerControlSession.isAllowed(from: .scrubPreview, to: .seeking))
        XCTAssertTrue(TVPlayerControlSession.isAllowed(from: .seeking, to: .timeshift))
        XCTAssertTrue(TVPlayerControlSession.isAllowed(from: .timeshift, to: .returningToLive))
        XCTAssertTrue(TVPlayerControlSession.isAllowed(from: .live, to: .scrubPreview))
        XCTAssertFalse(TVPlayerControlSession.isAllowed(from: .scrubPreview, to: .returningToLive))
        XCTAssertFalse(TVPlayerControlSession.isAllowed(from: .returningToLive, to: .scrubPreview))
    }

    func testSelectOpenOSDFocusTransportThenScrubPreviewThenOneSeekReload() async {
        let session = TVPlayerControlSession()
        session.noteControlsOpened(mediaIsCatchup: false)
        XCTAssertEqual(session.phase, .controls)

        let now = Date()
        XCTAssertTrue(session.beginScrub(
            absolute: now,
            windowStart: now.addingTimeInterval(-3600),
            playerTime: 0,
            isPlaying: true
        ))
        XCTAssertEqual(session.phase, .scrubPreview)
        for _ in 0 ..< 10 {
            session.applyPreviewDelta(
                -10,
                clamp: { $0 },
                windowStart: now.addingTimeInterval(-3600)
            )
        }
        XCTAssertEqual(session.previewMoveCount, 10)
        XCTAssertEqual(session.mediaReloadCount, 0)

        var reloads = 0
        XCTAssertTrue(session.tryBeginCommit(source: .select))
        await session.runSeek(reason: "test-commit") { generation in
            XCTAssertTrue(session.isSeekGenerationCurrent(generation))
            session.noteMediaReload(reason: "test-launch")
            reloads += 1
            session.finishSeek(mediaIsCatchup: true, keepControls: true)
        }
        XCTAssertEqual(reloads, 1)
        XCTAssertEqual(session.mediaReloadCount, 1)
        XCTAssertEqual(session.phase, .controls)
        XCTAssertFalse(session.isCommitInFlight)
    }

    func testTryBeginCommitSelectAndAutoCommitMutuallyExclusive() async {
        let session = TVPlayerControlSession()
        session.noteControlsOpened(mediaIsCatchup: false)
        _ = session.beginScrub(absolute: Date(), windowStart: nil, playerTime: 0, isPlaying: true)

        XCTAssertTrue(session.tryBeginCommit(source: .select))
        XCTAssertTrue(session.isCommitInFlight)
        // Auto-commit must not start a second commit while Select owns it.
        XCTAssertFalse(session.tryBeginCommit(source: .autoCommit))
        XCTAssertFalse(session.tryBeginCommit(source: .select))

        await session.runSeek(reason: "select-commit") { _ in
            session.noteMediaReload(reason: "once")
            session.finishSeek(mediaIsCatchup: true, keepControls: true)
        }
        XCTAssertEqual(session.mediaReloadCount, 1)
        XCTAssertFalse(session.isCommitInFlight)
    }

    func testAutoCommitTokenIgnoredWhenCommitAlreadyInFlight() async {
        let session = TVPlayerControlSession()
        session.noteControlsOpened(mediaIsCatchup: false)
        _ = session.beginScrub(absolute: Date(), windowStart: nil, playerTime: 0, isPlaying: true)
        _ = session.noteScrubStep(direction: .left, absoluteTimeline: true)
        try? await Task.sleep(nanoseconds: 750_000_000)
        XCTAssertGreaterThan(session.autoCommitToken, 0)

        XCTAssertTrue(session.tryBeginCommit(source: .autoCommit))
        XCTAssertFalse(session.tryBeginCommit(source: .autoCommit))
        await session.runSeek(reason: "auto") { _ in
            session.noteMediaReload(reason: "auto")
            session.finishSeek(mediaIsCatchup: true, keepControls: true)
        }
        XCTAssertEqual(session.mediaReloadCount, 1)
    }

    func testRapidSeekPressesCancelPriorGenerationSingleReload() async {
        let session = TVPlayerControlSession()
        session.noteControlsOpened(mediaIsCatchup: false)

        let slow = Task {
            await session.runSeek(reason: "slow") { generation in
                try? await Task.sleep(nanoseconds: 200_000_000)
                guard session.isSeekGenerationCurrent(generation) else { return }
                session.noteMediaReload(reason: "slow-reload")
                session.finishSeek(mediaIsCatchup: true, keepControls: true)
            }
        }
        try? await Task.sleep(nanoseconds: 20_000_000)
        await session.runSeek(reason: "fast") { generation in
            XCTAssertTrue(session.isSeekGenerationCurrent(generation))
            session.noteMediaReload(reason: "fast-reload")
            session.finishSeek(mediaIsCatchup: true, keepControls: true)
        }
        await slow.value
        XCTAssertEqual(session.mediaReloadCount, 1, "only the winning seek may reload media")
    }

    func testSeekTasksAtMostOneConcurrent() async {
        let session = TVPlayerControlSession()
        session.noteControlsOpened(mediaIsCatchup: false)
        var maxConcurrent = 0
        var concurrent = 0

        let a = Task {
            await session.runSeek(reason: "a") { generation in
                concurrent += 1
                maxConcurrent = max(maxConcurrent, concurrent)
                try? await Task.sleep(nanoseconds: 80_000_000)
                concurrent -= 1
                guard session.isSeekGenerationCurrent(generation) else { return }
                session.finishSeek(mediaIsCatchup: false, keepControls: true)
            }
        }
        try? await Task.sleep(nanoseconds: 10_000_000)
        let b = Task {
            await session.runSeek(reason: "b") { generation in
                concurrent += 1
                maxConcurrent = max(maxConcurrent, concurrent)
                try? await Task.sleep(nanoseconds: 40_000_000)
                concurrent -= 1
                guard session.isSeekGenerationCurrent(generation) else { return }
                session.finishSeek(mediaIsCatchup: false, keepControls: true)
            }
        }
        await a.value
        await b.value
        XCTAssertLessThanOrEqual(maxConcurrent, 1)
    }

    func testMenuCancelsScrubWithoutReload() {
        let session = TVPlayerControlSession()
        session.noteControlsOpened(mediaIsCatchup: false)
        XCTAssertTrue(session.beginScrub(
            absolute: Date(),
            windowStart: nil,
            playerTime: 12,
            isPlaying: true
        ))
        XCTAssertTrue(session.capturesMenu)
        XCTAssertTrue(session.cancelScrub())
        XCTAssertEqual(session.phase, .controls)
        XCTAssertEqual(session.mediaReloadCount, 0)
        XCTAssertFalse(session.capturesMenu)
    }

    func testReturnToLiveSingleReloadThenRewindAgain() async {
        let session = TVPlayerControlSession()
        session.transition(to: .timeshift, reason: "seed")
        session.noteControlsOpened(mediaIsCatchup: true)
        XCTAssertEqual(session.phase, .controls)

        await session.runSeek(reason: "go-live", asReturnToLive: true) { generation in
            XCTAssertEqual(session.phase, .returningToLive)
            session.noteMediaReload(reason: "returnToLive")
            session.finishReturnToLive(keepControls: false)
            _ = generation
        }
        XCTAssertEqual(session.mediaReloadCount, 1)
        XCTAssertEqual(session.phase, .live)

        session.noteControlsOpened(mediaIsCatchup: false)
        XCTAssertTrue(session.beginScrub(
            absolute: Date(),
            windowStart: nil,
            playerTime: 0,
            isPlaying: true
        ))
        XCTAssertEqual(session.phase, .scrubPreview)
        XCTAssertEqual(session.mediaReloadCount, 1)
    }

    func testChannelSurfBlockedDuringSeeking() async {
        let session = TVPlayerControlSession()
        XCTAssertTrue(session.allowsChannelSurf(controlsVisible: false, mediaIsLive: true))
        XCTAssertTrue(
            session.allowsChannelSurf(controlsVisible: true, mediaIsLive: true),
            "compact OSD may stay visible while surfing"
        )

        let seek = Task {
            await session.runSeek(reason: "in-flight") { _ in
                try? await Task.sleep(nanoseconds: 100_000_000)
                session.finishSeek(mediaIsCatchup: false, keepControls: false)
            }
        }
        try? await Task.sleep(nanoseconds: 10_000_000)
        XCTAssertTrue(session.isSeekInFlight)
        XCTAssertFalse(
            session.allowsChannelSurf(controlsVisible: false, mediaIsLive: true),
            "↑/↓ must not surf while seek/timeshift launch is in flight"
        )
        await seek.value
        XCTAssertTrue(session.allowsChannelSurf(controlsVisible: false, mediaIsLive: true))
    }

    func testChannelSurfAllowedWithOSDAfterCancellingScrub() {
        let session = TVPlayerControlSession()
        session.noteControlsOpened(mediaIsCatchup: false)
        XCTAssertTrue(session.allowsChannelSurf(controlsVisible: true, mediaIsLive: true))

        _ = session.beginScrub(absolute: Date(), windowStart: nil, playerTime: 0, isPlaying: false)
        XCTAssertFalse(session.allowsChannelSurf(controlsVisible: true, mediaIsLive: true))

        XCTAssertTrue(session.prepareChannelSurfWhileOSDVisible(mediaIsCatchup: false))
        XCTAssertFalse(session.isScrubbing)
        XCTAssertEqual(session.phase, .controls)
        XCTAssertTrue(session.allowsChannelSurf(controlsVisible: true, mediaIsLive: true))
        XCTAssertEqual(session.mediaReloadCount, 0)
    }

    func testPrepareSurfCancelsStaleSeekGeneration() async {
        let session = TVPlayerControlSession()
        session.noteControlsOpened(mediaIsCatchup: false)
        var completedStale = false
        let seek = Task {
            await session.runSeek(reason: "stale") { generation in
                try? await Task.sleep(nanoseconds: 80_000_000)
                guard session.isSeekGenerationCurrent(generation) else { return }
                completedStale = true
                session.noteMediaReload(reason: "stale")
                session.finishSeek(mediaIsCatchup: false, keepControls: true)
            }
        }
        try? await Task.sleep(nanoseconds: 10_000_000)
        XCTAssertTrue(session.isSeekInFlight)
        XCTAssertTrue(session.prepareChannelSurfWhileOSDVisible(mediaIsCatchup: false))
        await seek.value
        XCTAssertFalse(completedStale)
        XCTAssertEqual(session.mediaReloadCount, 0)
        XCTAssertTrue(session.allowsChannelSurf(controlsVisible: true, mediaIsLive: true))
    }

    func testOSDCloseLeavesLivePhaseSoSurfWorks() {
        let session = TVPlayerControlSession()
        session.noteControlsOpened(mediaIsCatchup: false)
        XCTAssertEqual(session.phase, .controls)
        XCTAssertTrue(
            session.allowsChannelSurf(controlsVisible: true, mediaIsLive: true),
            "↑/↓ surf while compact OSD is visible"
        )
        session.noteControlsClosed(mediaIsCatchup: false)
        XCTAssertEqual(session.phase, .live)
        XCTAssertTrue(session.allowsChannelSurf(controlsVisible: false, mediaIsLive: true))
    }

    func testResetForNewStreamInvalidatesSeekGenerationAndClearsCommit() async {
        let session = TVPlayerControlSession()
        session.noteControlsOpened(mediaIsCatchup: false)
        _ = session.beginScrub(absolute: Date(), windowStart: nil, playerTime: 0, isPlaying: true)
        XCTAssertTrue(session.tryBeginCommit(source: .select))

        var staleReloaded = false
        let stale = Task {
            await session.runSeek(reason: "stale") { generation in
                try? await Task.sleep(nanoseconds: 80_000_000)
                guard session.isSeekGenerationCurrent(generation) else { return }
                session.noteMediaReload(reason: "stale")
                staleReloaded = true
                session.finishSeek(mediaIsCatchup: true, keepControls: true)
            }
        }
        try? await Task.sleep(nanoseconds: 10_000_000)
        session.resetForNewStream(mediaIsCatchup: false)
        XCTAssertEqual(session.phase, .live)
        XCTAssertFalse(session.isCommitInFlight)
        XCTAssertNil(session.previewAbsoluteTime)
        await stale.value
        XCTAssertFalse(staleReloaded)
        XCTAssertEqual(session.mediaReloadCount, 0)
    }

    func testAutoReturnArmedOnlyOncePerTimeshiftClip() {
        let session = TVPlayerControlSession()
        session.resetForNewStream(mediaIsCatchup: true)
        XCTAssertTrue(session.tryConsumeAutoReturnToLive())
        XCTAssertFalse(session.tryConsumeAutoReturnToLive())
        // New timeshift clip re-arms.
        session.resetForNewStream(mediaIsCatchup: true)
        XCTAssertTrue(session.tryConsumeAutoReturnToLive())
    }

    func testTogglePlayAllowedDuringScrubPreviewBlockedDuringSeek() async {
        let session = TVPlayerControlSession()
        session.noteControlsOpened(mediaIsCatchup: false)
        XCTAssertTrue(session.allowsTogglePlay())
        _ = session.beginScrub(absolute: Date(), windowStart: nil, playerTime: 0, isPlaying: true)
        XCTAssertTrue(
            session.allowsTogglePlay(),
            "compact OSD Select toggles play during preview; auto-commit owns seek"
        )
        _ = session.cancelScrub()
        XCTAssertTrue(session.allowsTogglePlay())

        await session.runSeek(reason: "x") { _ in
            XCTAssertFalse(session.allowsTogglePlay())
            session.finishSeek(mediaIsCatchup: false, keepControls: true)
        }
        XCTAssertTrue(session.allowsTogglePlay())
    }

    func testScenarioReloadTable() async {
        let session = TVPlayerControlSession()
        session.noteControlsOpened(mediaIsCatchup: false)

        _ = session.beginScrub(absolute: Date(), windowStart: nil, playerTime: 0, isPlaying: true)
        for _ in 0 ..< 10 {
            session.applyPreviewDelta(-10, clamp: { $0 }, windowStart: nil)
        }
        XCTAssertEqual(session.mediaReloadCount, 0, "←/→ preview: 0 reloads")

        XCTAssertTrue(session.tryBeginCommit(source: .select))
        await session.runSeek(reason: "commit") { _ in
            session.noteMediaReload(reason: "timeshift")
            session.finishSeek(mediaIsCatchup: true, keepControls: true)
        }
        XCTAssertEqual(session.mediaReloadCount, 1, "Select commit: 1 reload")

        await session.runSeek(reason: "start-over") { _ in
            session.noteMediaReload(reason: "startOver")
            session.finishSeek(mediaIsCatchup: true, keepControls: true)
        }
        XCTAssertEqual(session.mediaReloadCount, 2, "Start Over: +1 reload")

        await session.runSeek(reason: "go-live", asReturnToLive: true) { _ in
            session.noteMediaReload(reason: "returnToLive")
            session.finishReturnToLive(keepControls: false)
        }
        XCTAssertEqual(session.mediaReloadCount, 3, "Go Live: +1 reload")
    }

    func testPreviewNudgeBlockedWhileCommitInFlight() {
        let session = TVPlayerControlSession()
        session.noteControlsOpened(mediaIsCatchup: false)
        let start = Date()
        _ = session.beginScrub(absolute: start, windowStart: start, playerTime: 0, isPlaying: true)
        XCTAssertTrue(session.tryBeginCommit(source: .select))
        session.applyPreviewDelta(-60, clamp: { $0 }, windowStart: start)
        XCTAssertEqual(session.previewAbsoluteTime, start, "preview must freeze once commit owns the pipeline")
        XCTAssertEqual(session.noteScrubStep(direction: .left, absoluteTimeline: true), 0)
    }

    func testScrubHoldAcceleratesOneThreeTenMinutes() {
        let session = TVPlayerControlSession()
        session.noteControlsOpened(mediaIsCatchup: false)
        _ = session.beginScrub(absolute: Date(), windowStart: nil, playerTime: 0, isPlaying: true)
        var steps: [TimeInterval] = []
        for _ in 0 ..< 10 {
            steps.append(session.noteScrubStep(direction: .right, absoluteTimeline: true))
        }
        XCTAssertEqual(steps[0], 60)
        XCTAssertEqual(steps[2], 60)
        XCTAssertEqual(steps[3], 180)
        XCTAssertEqual(steps[7], 180)
        XCTAssertEqual(steps[8], 600)
        XCTAssertEqual(steps[9], 600)
    }

    func testScrubAutoCommitFiresAfterIdleDebounce() async {
        let session = TVPlayerControlSession()
        session.noteControlsOpened(mediaIsCatchup: false)
        let start = Date()
        _ = session.beginScrub(absolute: start, windowStart: start, playerTime: 0, isPlaying: true)
        let tokenBefore = session.autoCommitToken
        _ = session.noteScrubStep(direction: .left, absoluteTimeline: true)
        XCTAssertEqual(session.autoCommitToken, tokenBefore, "token must not bump while still moving")
        try? await Task.sleep(nanoseconds: 750_000_000)
        XCTAssertEqual(session.autoCommitToken, tokenBefore + 1)
        XCTAssertTrue(session.isScrubbing, "debounce only signals; overlay performs commit")
    }

    func testScrubAutoCommitCancelledByExplicitCancel() async {
        let session = TVPlayerControlSession()
        session.noteControlsOpened(mediaIsCatchup: false)
        _ = session.beginScrub(absolute: Date(), windowStart: nil, playerTime: 0, isPlaying: true)
        let tokenBefore = session.autoCommitToken
        _ = session.noteScrubStep(direction: .right, absoluteTimeline: true)
        session.cancelAutoCommit()
        try? await Task.sleep(nanoseconds: 750_000_000)
        XCTAssertEqual(session.autoCommitToken, tokenBefore)
    }
}
