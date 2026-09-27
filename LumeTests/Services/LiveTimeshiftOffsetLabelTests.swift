//
//  LiveTimeshiftOffsetLabelTests.swift
//  LumeTests
//

import XCTest
@testable import Lume

final class LiveTimeshiftOffsetLabelTests: XCTestCase {
    func testNegativeOffsetIncludesMinutesAndSeconds() {
        let label = LiveTimeshift.liveOffsetLabel(-(11 * 60 + 35))
        XCTAssertTrue(label.hasPrefix("−") || label.hasPrefix("-"))
        XCTAssertTrue(label.contains("11"))
        XCTAssertTrue(label.contains("35"))
    }

    func testPositiveWholeMinutesOmitsZeroSeconds() {
        let label = LiveTimeshift.liveOffsetLabel(60)
        XCTAssertTrue(label.hasPrefix("+"))
        XCTAssertTrue(label.contains("1"))
        XCTAssertFalse(label.contains("sec") && label.contains("0 sec"))
    }
}
