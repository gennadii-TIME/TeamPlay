//
//  TVCompactPlayPauseChromeTests.swift
//  LumeTests
//
//  Glyph helpers still feed the OSD hint labels (OK · Pause / Continue).
//

import XCTest
@testable import Lume

final class TVCompactPlayPauseChromeTests: XCTestCase {
    func testGlyphNamePlayVersusPause() {
        XCTAssertEqual(TVCompactPlayPauseChrome.glyphName(isPlaying: true), "pause.fill")
        XCTAssertEqual(TVCompactPlayPauseChrome.glyphName(isPlaying: false), "play.fill")
    }

    func testStandardActionRowHasNoPlayPauseButton() {
        XCTAssertTrue(
            TVCompactOSDFocusModel.standardActions().isEmpty,
            "Play/Pause is timeline Select, not an action-row button"
        )
    }
}
