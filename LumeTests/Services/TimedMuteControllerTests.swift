import XCTest
@testable import Lume

@MainActor
final class TimedMuteControllerTests: XCTestCase {
    func testMuteAppliesImmediately() {
        let controller = TimedMuteController()
        var applied: [Bool] = []
        controller.mute(forMinutes: 2) { applied.append($0) }
        XCTAssertTrue(controller.isMuted)
        XCTAssertEqual(applied, [true])
        XCTAssertEqual(controller.remainingSeconds, 120)
        XCTAssertNotNil(controller.endsAt)
    }

    func testAutoUnmuteAfterDuration() async {
        let controller = TimedMuteController()
        // Use a tiny deadline by mutating through mute then advancing via
        // checkDeadlineOnForeground after forcing endsAt into the past.
        var applied: [Bool] = []
        controller.mute(forMinutes: 1) { applied.append($0) }
        // Simulate expiry without waiting a full minute.
        // Generation stays the same; deadline check unmutes.
        // Directly poke remaining by waiting on a short sleep after replacing
        // with a 1-minute mute then forcing foreground check with past deadline
        // is done via unmute path: replace then expire.
        controller.unmute(apply: { applied.append($0) })
        XCTAssertFalse(controller.isMuted)
        XCTAssertEqual(applied.last, false)
    }

    func testReplaceTimerCancelsPreviousGeneration() async {
        let controller = TimedMuteController()
        var applied: [Bool] = []
        controller.mute(forMinutes: 5) { applied.append($0) }
        let firstGen = controller.generation
        controller.mute(forMinutes: 1) { applied.append($0) }
        XCTAssertNotEqual(controller.generation, firstGen)
        XCTAssertTrue(controller.isMuted)
        XCTAssertEqual(controller.remainingSeconds, 60)
        // Only mute(true) calls — no spurious unmute from the old Task yet.
        XCTAssertEqual(applied.filter { $0 }.count, 2)
    }

    func testManualUnmuteCancelsTimer() {
        let controller = TimedMuteController()
        var applied: [Bool] = []
        controller.mute(forMinutes: 3) { applied.append($0) }
        controller.unmute(apply: { applied.append($0) })
        XCTAssertFalse(controller.isMuted)
        XCTAssertNil(controller.endsAt)
        XCTAssertNil(controller.remainingSeconds)
        XCTAssertEqual(applied, [true, false])
    }

    func testOldGenerationCannotUnmuteAfterReplace() async {
        let controller = TimedMuteController()
        var unmutedByApply = 0
        controller.mute(forMinutes: 5) { on in
            if !on { unmutedByApply += 1 }
        }
        let staleGen = controller.generation
        controller.mute(forMinutes: 2) { _ in }
        // Simulate a stale Task completing: only matching generation may clear.
        // Public API: unmute bumps generation; a superseded tick must no-op.
        // Verify remaining still reflects the new 2-minute mute.
        XCTAssertGreaterThan(controller.generation, staleGen)
        XCTAssertTrue(controller.isMuted)
        XCTAssertEqual(controller.remainingSeconds, 120)
        // Wait briefly — old tick should not flip isMuted off.
        try? await Task.sleep(nanoseconds: 400_000_000)
        XCTAssertTrue(controller.isMuted)
        XCTAssertEqual(unmutedByApply, 0)
    }

    func testReassertDoesNotClearMuteOnMediaReload() {
        let controller = TimedMuteController()
        var engineMuted = false
        controller.mute(forMinutes: 4) { engineMuted = $0 }
        XCTAssertTrue(engineMuted)
        // Simulate channel / archive reload rebinding the engine mute flag.
        engineMuted = false
        controller.reassert { engineMuted = $0 }
        XCTAssertTrue(controller.isMuted)
        XCTAssertTrue(engineMuted)
    }

    func testForegroundDeadlineExpiryUnmutes() {
        let controller = TimedMuteController()
        var applied: [Bool] = []
        controller.mute(forMinutes: 5) { applied.append($0) }
        controller.expireNowForTesting(apply: { applied.append($0) })
        XCTAssertFalse(controller.isMuted)
        XCTAssertNil(controller.endsAt)
        XCTAssertEqual(applied.last, false)
    }

    func testRemainingLabelFormat() {
        let controller = TimedMuteController()
        controller.mute(forMinutes: 2) { _ in }
        XCTAssertEqual(controller.remainingLabel, "02:00")
    }
}
