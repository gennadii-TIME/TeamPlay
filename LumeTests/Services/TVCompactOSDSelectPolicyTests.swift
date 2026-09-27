//
//  TVCompactOSDSelectPolicyTests.swift
//  LumeTests
//

import XCTest
@testable import Lume

final class TVCompactOSDSelectPolicyTests: XCTestCase {
    func testHiddenSelectOpensOSDOnly() {
        let action = TVCompactOSDSelectPolicy.resolve(
            osdVisible: false,
            isCommitInFlight: false,
            isSeekInFlight: false
        )
        XCTAssertEqual(action, .openOSDOnly)
    }

    func testVisibleSelectTogglesPlay() {
        XCTAssertEqual(
            TVCompactOSDSelectPolicy.resolve(
                osdVisible: true,
                isCommitInFlight: false,
                isSeekInFlight: false
            ),
            .togglePlay
        )
    }

    func testSelectIgnoredWhileCommitInFlight() {
        XCTAssertEqual(
            TVCompactOSDSelectPolicy.resolve(
                osdVisible: true,
                isCommitInFlight: true,
                isSeekInFlight: false
            ),
            .ignore
        )
    }

    func testSelectIgnoredWhileSeekInFlight() {
        XCTAssertEqual(
            TVCompactOSDSelectPolicy.resolve(
                osdVisible: true,
                isCommitInFlight: false,
                isSeekInFlight: true
            ),
            .ignore
        )
    }

    func testSelectNeverImpliesScrubCommit() {
        // Policy surface has no commit action — auto-commit owns seek.
        let cases: [(Bool, Bool, Bool)] = [
            (false, false, false),
            (true, false, false),
            (true, true, false),
            (true, false, true)
        ]
        for (visible, commit, seek) in cases {
            let action = TVCompactOSDSelectPolicy.resolve(
                osdVisible: visible,
                isCommitInFlight: commit,
                isSeekInFlight: seek
            )
            XCTAssertNotEqual(action.rawValue, "commit")
        }
    }
}

@MainActor
final class TVCompactOSDSelectGateTests: XCTestCase {
    func testAppleAndCECDedupedToOneToggle() {
        let gate = TVCompactOSDSelectGate()
        let t = Date(timeIntervalSince1970: 7_000_000)
        XCTAssertTrue(gate.shouldAccept(now: t))
        XCTAssertFalse(gate.shouldAccept(now: t.addingTimeInterval(0.05)))
        XCTAssertTrue(gate.shouldAccept(now: t.addingTimeInterval(0.2)))
    }
}

@MainActor
final class TVCompactOSDPlayToggleDuringScrubTests: XCTestCase {
    func testAllowsToggleDuringScrubPreviewButNotDuringCommit() {
        let session = TVPlayerControlSession()
        session.noteControlsOpened(mediaIsCatchup: false)
        XCTAssertTrue(session.allowsTogglePlay())

        XCTAssertTrue(session.beginScrub(
            absolute: Date(),
            windowStart: nil,
            playerTime: 0,
            isPlaying: true
        ))
        XCTAssertTrue(session.allowsTogglePlay(), "preview must allow Pause/Play")

        session.notePlaybackDesireDuringPreview(isPlaying: false)
        XCTAssertFalse(session.wasPlayingBeforeScrub)

        XCTAssertTrue(session.tryBeginCommit(source: .autoCommit))
        XCTAssertFalse(session.allowsTogglePlay(), "active commit must block toggle")
    }

    func testSelectDoesNotBeginSecondCommitWhileAutoCommitOwnsPipeline() async {
        let session = TVPlayerControlSession()
        session.noteControlsOpened(mediaIsCatchup: false)
        _ = session.beginScrub(absolute: Date(), windowStart: nil, playerTime: 0, isPlaying: true)
        XCTAssertTrue(session.tryBeginCommit(source: .autoCommit))
        XCTAssertFalse(session.tryBeginCommit(source: .select))
        XCTAssertFalse(session.tryBeginCommit(source: .autoCommit))

        await session.runSeek(reason: "auto") { _ in
            session.noteMediaReload(reason: "once")
            session.finishSeek(mediaIsCatchup: true, keepControls: true)
        }
        XCTAssertEqual(session.mediaReloadCount, 1)
    }

    func testPlayPauseButtonAbsentFromStandardActions() {
        XCTAssertTrue(TVCompactOSDFocusModel.standardActions().isEmpty)
        let model = TVCompactOSDFocusModel.initial(
            timelineAvailable: true,
            actions: TVCompactOSDFocusModel.standardActions()
        )
        XCTAssertEqual(model.zone, .timeline)
        XCTAssertTrue(model.availableActions.isEmpty)
    }
}
