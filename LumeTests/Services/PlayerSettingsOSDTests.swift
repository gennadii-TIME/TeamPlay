//
//  PlayerSettingsOSDTests.swift
//  LumeTests
//

import XCTest
@testable import Lume

final class PlayerSettingsOSDTests: XCTestCase {
    func testHideDelayDefaultsToFiveWhenUnsetOrInvalid() {
        XCTAssertEqual(PlayerSettings.OSD.clamped(0), 5)
        XCTAssertEqual(PlayerSettings.OSD.clamped(4), 5)
        XCTAssertEqual(PlayerSettings.OSD.clamped(11), 5)
        XCTAssertEqual(PlayerSettings.OSD.hideDelaySecondsDefault, 5)
    }

    func testHideDelayAcceptsFiveThroughTen() {
        XCTAssertEqual(PlayerSettings.OSD.hideDelaySecondsOptions, [5, 6, 7, 8, 9, 10])
        for value in 5 ... 10 {
            XCTAssertEqual(PlayerSettings.OSD.clamped(value), value)
        }
    }
}
