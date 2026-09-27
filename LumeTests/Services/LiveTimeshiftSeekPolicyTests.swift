//
//  LiveTimeshiftSeekPolicyTests.swift
//  LumeTests
//
//  In-clip seek must use archive window + seekable range — never `duration > 1`
//  as the sole gate.
//

import XCTest
@testable import Lume

final class LiveTimeshiftSeekPolicyTests: XCTestCase {
    func testSeekWithinClipWhenDurationUnknownButSeekableRangeCoversOffset() {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let end = start.addingTimeInterval(3600)
        let target = start.addingTimeInterval(120)

        let result = LiveTimeshift.inClipSeekOffset(
            target: target,
            clipStart: start,
            clipEnd: end,
            seekableStart: 0,
            seekableEnd: 600
        )
        XCTAssertEqual(try XCTUnwrap(result), 120, accuracy: 0.01)
    }

    func testSeekRejectedWhenTargetOutsideClipBoundsEvenIfDurationLarge() {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let end = start.addingTimeInterval(600)
        let target = start.addingTimeInterval(900)

        let result = LiveTimeshift.inClipSeekOffset(
            target: target,
            clipStart: start,
            clipEnd: end,
            seekableStart: 0,
            seekableEnd: 10_000
        )
        XCTAssertNil(result)
    }

    func testSeekRejectedWhenOffsetOutsideSeekableRange() {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let end = start.addingTimeInterval(3600)
        let target = start.addingTimeInterval(50)

        let result = LiveTimeshift.inClipSeekOffset(
            target: target,
            clipStart: start,
            clipEnd: end,
            seekableStart: 0,
            seekableEnd: 30
        )
        XCTAssertNil(result)
    }

    func testZeroClockDurationDoesNotBlockInClipSeek() {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let end = start.addingTimeInterval(1800)
        let target = start.addingTimeInterval(90)

        // Engine has not reported duration yet (0), but seekable end is known.
        let result = LiveTimeshift.inClipSeekOffset(
            target: target,
            clipStart: start,
            clipEnd: end,
            seekableStart: 0,
            seekableEnd: 1800
        )
        XCTAssertEqual(try XCTUnwrap(result), 90, accuracy: 0.01)
    }
}
