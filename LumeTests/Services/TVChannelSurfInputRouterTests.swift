//
//  TVChannelSurfInputRouterTests.swift
//  LumeTests
//
//  Clean-screen ↑/↓ surfing gates and MoveCommand+UIPress dedupe.
//

import XCTest
@testable import Lume

@MainActor
final class TVChannelSurfInputRouterTests: XCTestCase {
    private func cleanGate(allows: Bool = true) -> TVChannelSurfGate {
        TVChannelSurfGate(
            isOSDVisible: false,
            hasOpenPanel: false,
            isScrubbing: false,
            allowsChannelSurf: allows
        )
    }

    func testCleanScreenUpAccepted() {
        let router = TVChannelSurfInputRouter()
        let d = router.evaluate(
            direction: .up,
            source: .moveCommand,
            gate: cleanGate(),
            phase: "live",
            focusTarget: "catcher",
            channelID: "ch-1"
        )
        XCTAssertTrue(d.accepted)
    }

    func testCleanScreenDownAccepted() {
        let router = TVChannelSurfInputRouter()
        let d = router.evaluate(
            direction: .down,
            source: .uiPress,
            gate: cleanGate(),
            phase: "live",
            focusTarget: "catcher",
            channelID: "ch-1"
        )
        XCTAssertTrue(d.accepted)
    }

    func testOSDVisibleAllowsSurfWhenSessionAllows() {
        let router = TVChannelSurfInputRouter()
        var gate = cleanGate()
        gate.isOSDVisible = true
        let d = router.evaluate(
            direction: .up,
            source: .moveCommand,
            gate: gate,
            phase: "controls",
            focusTarget: "timeline",
            channelID: "ch-1"
        )
        XCTAssertTrue(d.accepted, "compact OSD must allow ↑/↓ SurfCursor")
    }

    func testOpenPanelRejectsSurf() {
        let router = TVChannelSurfInputRouter()
        var gate = cleanGate()
        gate.hasOpenPanel = true
        let d = router.evaluate(
            direction: .down,
            source: .moveCommand,
            gate: gate,
            phase: "controls",
            focusTarget: "channel",
            channelID: "ch-1"
        )
        XCTAssertFalse(d.accepted)
        XCTAssertEqual(d.reason, "panel-open")
    }

    func testScrubbingRejectsSurf() {
        let router = TVChannelSurfInputRouter()
        var gate = cleanGate()
        gate.isScrubbing = true
        let d = router.evaluate(
            direction: .up,
            source: .moveCommand,
            gate: gate,
            phase: "scrubPreview",
            focusTarget: "scrubber",
            channelID: "ch-1"
        )
        XCTAssertFalse(d.accepted)
        XCTAssertEqual(d.reason, "scrubbing")
    }

    func testSessionBlockedDuringSeek() {
        let router = TVChannelSurfInputRouter()
        let d = router.evaluate(
            direction: .up,
            source: .moveCommand,
            gate: cleanGate(allows: false),
            phase: "seeking",
            focusTarget: "catcher",
            channelID: "ch-1"
        )
        XCTAssertFalse(d.accepted)
        XCTAssertEqual(d.reason, "session-blocked")
    }

    func testSettledAfterSeekAllowsSurfAgain() {
        let router = TVChannelSurfInputRouter()
        XCTAssertFalse(
            router.evaluate(
                direction: .up,
                source: .moveCommand,
                gate: cleanGate(allows: false),
                phase: "seeking",
                focusTarget: "catcher",
                channelID: nil
            ).accepted
        )
        XCTAssertTrue(
            router.evaluate(
                direction: .up,
                source: .moveCommand,
                gate: cleanGate(allows: true),
                phase: "live",
                focusTarget: "catcher",
                channelID: nil
            ).accepted
        )
    }

    func testDuplicateMoveCommandAndUIPressSingleAccept() {
        let router = TVChannelSurfInputRouter()
        let t0 = Date(timeIntervalSince1970: 2_000_000)
        let first = router.evaluate(
            direction: .up,
            source: .moveCommand,
            gate: cleanGate(),
            phase: "live",
            focusTarget: "catcher",
            channelID: "a",
            now: t0
        )
        let twin = router.evaluate(
            direction: .up,
            source: .uiPress,
            gate: cleanGate(),
            phase: "live",
            focusTarget: "catcher",
            channelID: "a",
            now: t0.addingTimeInterval(0.02)
        )
        XCTAssertTrue(first.accepted)
        XCTAssertFalse(twin.accepted)
        XCTAssertEqual(twin.reason, "deduped")
    }

    func testTenDistinctPressesTenAccepts() {
        let router = TVChannelSurfInputRouter()
        var accepted = 0
        let t0 = Date(timeIntervalSince1970: 3_000_000)
        for i in 0 ..< 10 {
            // Space presses beyond the dedupe window so each is a new physical tap.
            let now = t0.addingTimeInterval(Double(i) * (TVChannelSurfInputRouter.dedupeWindow + 0.05))
            let d = router.evaluate(
                direction: i.isMultiple(of: 2) ? .up : .down,
                source: .moveCommand,
                gate: cleanGate(),
                phase: "live",
                focusTarget: "catcher",
                channelID: "ch-\(i)",
                now: now
            )
            if d.accepted { accepted += 1 }
        }
        XCTAssertEqual(accepted, 10)
    }

    func testAppleRemoteAndCECSameAcceptPath() {
        let apple = TVChannelSurfInputRouter()
        let cec = TVChannelSurfInputRouter()
        let t = Date(timeIntervalSince1970: 4_000_000)
        let a = apple.evaluate(
            direction: .down,
            source: .moveCommand,
            gate: cleanGate(),
            phase: "live",
            focusTarget: "catcher",
            channelID: "x",
            now: t
        )
        let c = cec.evaluate(
            direction: .down,
            source: .cec,
            gate: cleanGate(),
            phase: "live",
            focusTarget: "catcher",
            channelID: "x",
            now: t
        )
        XCTAssertEqual(a.accepted, c.accepted)
        XCTAssertTrue(a.accepted)
    }
}
