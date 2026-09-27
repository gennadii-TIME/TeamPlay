//
//  TVCompactOSDFocusModelTests.swift
//  LumeTests
//

import XCTest
@testable import Lume

final class TVCompactOSDFocusModelTests: XCTestCase {
    private func model(
        timeline: Bool = true,
        actions: [TVCompactOSDAction] = TVCompactOSDFocusModel.standardActions()
    ) -> TVCompactOSDFocusModel {
        .initial(timelineAvailable: timeline, actions: actions)
    }

    func testInitialLandsOnTimelineWhenActionRowEmpty() {
        let m = model()
        XCTAssertEqual(m.zone, .timeline)
        XCTAssertTrue(m.availableActions.isEmpty)
    }

    func testTimelineDownWithEmptyActionsIsNoOp() {
        var m = model()
        XCTAssertFalse(m.move(.down).didChange)
        XCTAssertEqual(m.zone, .timeline)
    }

    func testTimelineDownMovesToFirstActionWhenPresent() {
        var m = model(actions: [
            .init(id: .playPause, isAvailable: true)
        ])
        m.zone = .timeline
        let change = m.move(.down)
        XCTAssertTrue(change.didChange)
        XCTAssertEqual(change.zone, .actions)
        XCTAssertEqual(change.actionID, .playPause)
    }

    func testActionUpMovesToTimeline() {
        var m = model(actions: [
            .init(id: .playPause, isAvailable: true)
        ])
        m.zone = .actions
        m.actionIndex = 0
        let change = m.move(.up)
        XCTAssertTrue(change.didChange)
        XCTAssertEqual(change.zone, .timeline)
        XCTAssertNil(change.actionID)
    }

    func testActionLeftRightMovesBetweenNeighbors() {
        var m = model(actions: [
            .init(id: .playPause, isAvailable: true),
            .init(id: .playPause, isAvailable: true)
        ])
        m.zone = .actions
        m.actionIndex = 0
        XCTAssertTrue(m.move(.right).didChange)
        XCTAssertEqual(m.actionIndex, 1)
        XCTAssertTrue(m.move(.left).didChange)
        XCTAssertEqual(m.actionIndex, 0)
    }

    func testDisabledActionIsSkippedOnReconcile() {
        var m = model(actions: [
            .init(id: .playPause, isAvailable: false)
        ])
        XCTAssertEqual(m.zone, .timeline)

        m.zone = .actions
        m.actionIndex = 0
        m.actions = [.init(id: .playPause, isAvailable: false)]
        let change = m.reconcile()
        XCTAssertTrue(change.didChange)
        XCTAssertEqual(m.zone, .timeline)
    }

    func testDynamicAddRemoveKeepsNearestFocus() {
        var m = model(actions: [
            .init(id: .playPause, isAvailable: true)
        ])
        m.zone = .actions
        m.actionIndex = 0

        m.actions = [
            .init(id: .playPause, isAvailable: true),
            .init(id: .playPause, isAvailable: true)
        ]
        _ = m.reconcile()
        XCTAssertEqual(m.zone, .actions)
        XCTAssertEqual(m.actionIndex, 0)

        m.actionIndex = 1
        m.actions = [.init(id: .playPause, isAvailable: true)]
        _ = m.reconcile()
        XCTAssertEqual(m.zone, .actions)
        XCTAssertEqual(m.actionIndex, 0)
        XCTAssertEqual(m.focusedActionID, .playPause)
    }

    func testPlayPauseStateChangePreservesTimelineFocus() {
        var m = model()
        XCTAssertEqual(m.zone, .timeline)
        let before = m
        _ = m.noteActionPresentationChanged()
        XCTAssertEqual(m.zone, before.zone)
        XCTAssertNil(m.focusedActionID)
    }

    func testTimelineLeftRightDoNotChangeFocusZone() {
        var m = model()
        m.zone = .timeline
        XCTAssertFalse(m.move(.left).didChange)
        XCTAssertFalse(m.move(.right).didChange)
        XCTAssertEqual(m.zone, .timeline)
    }

    func testFocusRingContractDoesNotOwnHitTesting() {
        XCTAssertEqual(TVCompactOSDFocusRing.lineWidth, 2)
        XCTAssertEqual(TVCompactOSDFocusRing.fillOpacity, 0.14, accuracy: 0.0001)
    }
}

@MainActor
final class TVCompactOSDFocusInputGateTests: XCTestCase {
    func testAppleMoveCommandAndCECareDeduped() {
        let gate = TVCompactOSDFocusInputGate()
        let t = Date(timeIntervalSince1970: 5_000_000)
        XCTAssertTrue(gate.shouldAccept(.up, now: t))
        XCTAssertFalse(gate.shouldAccept(.up, now: t.addingTimeInterval(0.05)))
        XCTAssertTrue(gate.shouldAccept(.up, now: t.addingTimeInterval(0.2)))
    }

    func testOppositeDirectionsAreNotDeduped() {
        let gate = TVCompactOSDFocusInputGate()
        let t = Date(timeIntervalSince1970: 5_000_000)
        XCTAssertTrue(gate.shouldAccept(.down, now: t))
        XCTAssertTrue(gate.shouldAccept(.up, now: t.addingTimeInterval(0.01)))
    }
}

@MainActor
final class TVCompactOSDChannelSurfIsolationTests: XCTestCase {
    func testOSDVisibleRejectsChannelSurfOnlyWhenSessionBlocked() {
        let router = TVChannelSurfInputRouter()
        let openGate = TVChannelSurfGate(
            isOSDVisible: true,
            hasOpenPanel: false,
            isScrubbing: false,
            allowsChannelSurf: true
        )
        XCTAssertTrue(
            router.evaluate(
                direction: .up,
                source: .cec,
                gate: openGate,
                phase: "controls",
                focusTarget: "timeline",
                channelID: "ch"
            ).accepted
        )

        let blocked = TVChannelSurfGate(
            isOSDVisible: true,
            hasOpenPanel: false,
            isScrubbing: false,
            allowsChannelSurf: false
        )
        let d = router.evaluate(
            direction: .up,
            source: .cec,
            gate: blocked,
            phase: "seeking",
            focusTarget: "timeline",
            channelID: "ch"
        )
        XCTAssertFalse(d.accepted)
        XCTAssertEqual(d.reason, "session-blocked")
    }

    func testOSDHiddenAllowsChannelSurf() {
        let router = TVChannelSurfInputRouter()
        let gate = TVChannelSurfGate(
            isOSDVisible: false,
            hasOpenPanel: false,
            isScrubbing: false,
            allowsChannelSurf: true
        )
        XCTAssertTrue(
            router.evaluate(
                direction: .down,
                source: .moveCommand,
                gate: gate,
                phase: "live",
                focusTarget: "catcher",
                channelID: "ch"
            ).accepted
        )
    }

    func testAppleAndSamsungCECSameSurfRejectWhenOSDVisible() {
        let router = TVChannelSurfInputRouter()
        let gate = TVChannelSurfGate(
            isOSDVisible: true,
            hasOpenPanel: true,
            isScrubbing: false,
            allowsChannelSurf: true
        )
        let apple = router.evaluate(
            direction: .up,
            source: .moveCommand,
            gate: gate,
            phase: "controls",
            focusTarget: "timeline",
            channelID: "ch",
            now: Date(timeIntervalSince1970: 9)
        )
        let cec = router.evaluate(
            direction: .up,
            source: .cec,
            gate: gate,
            phase: "controls",
            focusTarget: "timeline",
            channelID: "ch",
            now: Date(timeIntervalSince1970: 9.05)
        )
        XCTAssertEqual(apple.accepted, cec.accepted)
        XCTAssertFalse(apple.accepted)
        XCTAssertEqual(apple.reason, "panel-open")
    }
}
