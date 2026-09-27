//
//  OSDProgramInfoTests.swift
//  LumeTests
//

import XCTest
@testable import Lume

final class OSDProgramInfoTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_700_000_000)

    private func listings() -> [OSDProgramInfo] {
        [
            OSDProgramInfo(
                title: "A",
                start: t0,
                end: t0.addingTimeInterval(3600),
                listingDescription: "desc-a"
            ),
            OSDProgramInfo(
                title: "B",
                start: t0.addingTimeInterval(3600),
                end: t0.addingTimeInterval(7200),
                listingDescription: ""
            ),
            OSDProgramInfo(
                title: "C",
                start: t0.addingTimeInterval(7200),
                end: t0.addingTimeInterval(10_800)
            )
        ]
    }

    func testAtFindsHalfOpenInterval() {
        let guide = listings()
        XCTAssertEqual(OSDProgramInfo.at(t0, in: guide)?.title, "A")
        XCTAssertEqual(
            OSDProgramInfo.at(t0.addingTimeInterval(3599), in: guide)?.title,
            "A"
        )
        XCTAssertEqual(
            OSDProgramInfo.at(t0.addingTimeInterval(3600), in: guide)?.title,
            "B"
        )
    }

    func testAtReturnsNilInGapOrOutside() {
        let guide = listings()
        XCTAssertNil(OSDProgramInfo.at(t0.addingTimeInterval(-1), in: guide))
        XCTAssertNil(OSDProgramInfo.at(t0.addingTimeInterval(20_000), in: guide))
    }

    func testNextAfterPreview() {
        let guide = listings()
        XCTAssertEqual(
            OSDProgramInfo.next(after: t0.addingTimeInterval(100), in: guide)?.title,
            "B"
        )
        XCTAssertNil(OSDProgramInfo.next(after: t0.addingTimeInterval(8000), in: guide))
    }
}
