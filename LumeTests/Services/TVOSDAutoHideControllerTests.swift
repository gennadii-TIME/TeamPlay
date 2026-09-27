//
//  TVOSDAutoHideControllerTests.swift
//  LumeTests
//

import XCTest
@testable import Lume

final class TVOSDAutoHidePolicyTests: XCTestCase {
    func testHideAfter5Seconds() {
        let now = Date(timeIntervalSince1970: 1_000)
        let deadline = TVOSDAutoHidePolicy.deadline(from: now, delay: 5)
        XCTAssertFalse(
            TVOSDAutoHidePolicy.shouldHide(
                now: now.addingTimeInterval(4.9),
                deadline: deadline,
                isBlocked: false
            )
        )
        XCTAssertTrue(
            TVOSDAutoHidePolicy.shouldHide(
                now: now.addingTimeInterval(5),
                deadline: deadline,
                isBlocked: false
            )
        )
    }

    func testHideAfter10Seconds() {
        let now = Date(timeIntervalSince1970: 2_000)
        let deadline = TVOSDAutoHidePolicy.deadline(from: now, delay: 10)
        XCTAssertFalse(
            TVOSDAutoHidePolicy.shouldHide(
                now: now.addingTimeInterval(9.9),
                deadline: deadline,
                isBlocked: false
            )
        )
        XCTAssertTrue(
            TVOSDAutoHidePolicy.shouldHide(
                now: now.addingTimeInterval(10),
                deadline: deadline,
                isBlocked: false
            )
        )
    }

    func testRemoteInteractionRestartsDeadline() {
        XCTAssertTrue(TVOSDAutoHidePolicy.shouldRestartDeadline(for: .userInteraction))
        let t0 = Date(timeIntervalSince1970: 100)
        let first = TVOSDAutoHidePolicy.deadline(from: t0, delay: 5)
        let afterRemote = TVOSDAutoHidePolicy.deadline(from: t0.addingTimeInterval(2), delay: 5)
        XCTAssertEqual(first.timeIntervalSince1970, 105)
        XCTAssertEqual(afterRemote.timeIntervalSince1970, 107)
    }

    func testPlaybackClockUpdatesDoNotRestartDeadline() {
        XCTAssertFalse(TVOSDAutoHidePolicy.shouldRestartDeadline(for: .playbackClockTick))
        XCTAssertFalse(TVOSDAutoHidePolicy.shouldRestartDeadline(for: .epgOrChromeTextUpdate))
    }

    func testScrubBlocksHideThenSettledRestarts() {
        let now = Date(timeIntervalSince1970: 500)
        let deadline = TVOSDAutoHidePolicy.deadline(from: now, delay: 5)
        XCTAssertFalse(TVOSDAutoHidePolicy.shouldRestartDeadline(for: .scrubOrSeekActive))
        XCTAssertFalse(
            TVOSDAutoHidePolicy.shouldHide(
                now: now.addingTimeInterval(6),
                deadline: deadline,
                isBlocked: true
            ),
            "active scrub/seek must block hide even after deadline"
        )
        XCTAssertTrue(TVOSDAutoHidePolicy.shouldRestartDeadline(for: .scrubOrSeekSettled))
        let restarted = TVOSDAutoHidePolicy.deadline(from: now.addingTimeInterval(6), delay: 5)
        XCTAssertEqual(restarted.timeIntervalSince1970, 511)
        XCTAssertTrue(
            TVOSDAutoHidePolicy.shouldHide(
                now: restarted,
                deadline: restarted,
                isBlocked: false
            )
        )
    }

    func testHideBlockedWhilePanelOrScrub() {
        XCTAssertTrue(
            TVOSDAutoHidePolicy.isHideBlocked(
                isControlsVisible: true,
                isPanelOpen: true,
                isScrubbing: false,
                isSeekInFlight: false
            )
        )
        XCTAssertTrue(
            TVOSDAutoHidePolicy.isHideBlocked(
                isControlsVisible: true,
                isPanelOpen: false,
                isScrubbing: true,
                isSeekInFlight: false
            )
        )
        XCTAssertTrue(
            TVOSDAutoHidePolicy.isHideBlocked(
                isControlsVisible: true,
                isPanelOpen: false,
                isScrubbing: false,
                isSeekInFlight: true
            )
        )
        XCTAssertFalse(
            TVOSDAutoHidePolicy.isHideBlocked(
                isControlsVisible: true,
                isPanelOpen: false,
                isScrubbing: false,
                isSeekInFlight: false
            )
        )
    }
}

@MainActor
final class TVOSDAutoHideControllerTests: XCTestCase {
    func testUserInteractionArmsDeadlineWithoutPlaybackGate() async {
        var now = Date(timeIntervalSince1970: 0)
        var blocked = false
        var hideCount = 0
        let controller = TVOSDAutoHideController(
            delayProvider: { 5 },
            nowProvider: { now },
            isBlocked: { blocked },
            onHide: { hideCount += 1 }
        )

        controller.noteUserInteraction()
        XCTAssertEqual(controller.deadline?.timeIntervalSince1970, 5)

        now = Date(timeIntervalSince1970: 1)
        controller.notePlaybackClockTick()
        XCTAssertEqual(
            controller.deadline?.timeIntervalSince1970,
            5,
            "playback clock must not move the deadline"
        )

        controller.noteUserInteraction()
        XCTAssertEqual(controller.deadline?.timeIntervalSince1970, 6)

        blocked = true
        controller.schedule(from: now)
        XCTAssertNil(controller.deadline)

        blocked = false
        controller.noteScrubOrSeekSettled()
        XCTAssertEqual(controller.deadline?.timeIntervalSince1970, 6)

        controller.cancel()
        XCTAssertNil(controller.deadline)
        XCTAssertEqual(hideCount, 0)
    }
}
