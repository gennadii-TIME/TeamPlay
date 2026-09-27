//
//  DeepArchiveSeekPolicyTests.swift
//  LumeTests
//
//  Absolute catchup / timeshift scrub must never silent-no-op: either rebuild
//  the archive URL (launchTimeshift) or surface a visible failure. In-engine
//  seek is not used on this path — deep archive often reports duration yet
//  ignores seek.
//

import XCTest
@testable import Lume

final class DeepArchiveSeekPolicyTests: XCTestCase {
    private let clipStart = Date(timeIntervalSince1970: 1_700_000_000)
    private var clipEnd: Date { clipStart.addingTimeInterval(3600) }

    func testDurationZeroRequiresTimeshiftReload() {
        let target = clipStart.addingTimeInterval(120)
        XCTAssertEqual(
            DeepArchiveSeekPolicy.decide(
                target: target,
                clipStart: clipStart,
                clipEnd: clipEnd,
                duration: 0,
                seekableStart: 0,
                seekableEnd: 3600
            ),
            .launchTimeshift
        )
    }

    func testReportedDurationStillRequiresTimeshiftReload() {
        // Deep archive often reports a finite duration while engine seek is a
        // no-op — absolute scrub must still rebuild the URL.
        let target = clipStart.addingTimeInterval(120)
        XCTAssertEqual(
            DeepArchiveSeekPolicy.decide(
                target: target,
                clipStart: clipStart,
                clipEnd: clipEnd,
                duration: 1800,
                seekableStart: 0,
                seekableEnd: 1800
            ),
            .launchTimeshift
        )
    }

    func testEmptySeekableRangeRequiresTimeshiftReload() {
        let target = clipStart.addingTimeInterval(120)
        XCTAssertEqual(
            DeepArchiveSeekPolicy.decide(
                target: target,
                clipStart: clipStart,
                clipEnd: clipEnd,
                duration: 1800,
                seekableStart: nil,
                seekableEnd: nil
            ),
            .launchTimeshift
        )
    }

    func testTargetOutsideClipRequiresTimeshiftReload() {
        let target = clipStart.addingTimeInterval(4000)
        XCTAssertEqual(
            DeepArchiveSeekPolicy.decide(
                target: target,
                clipStart: clipStart,
                clipEnd: clipEnd,
                duration: 10_000,
                seekableStart: 0,
                seekableEnd: 10_000
            ),
            .launchTimeshift
        )
    }

    func testSingleDecideYieldsExactlyOneLaunchTimeshift() {
        var engine = 0
        var reload = 0
        switch DeepArchiveSeekPolicy.decide(
            target: clipStart.addingTimeInterval(90),
            clipStart: clipStart,
            clipEnd: clipEnd,
            duration: 1800,
            seekableStart: 0,
            seekableEnd: 1800
        ) {
        case .engineSeek: engine = 1
        case .launchTimeshift: reload = 1
        }
        XCTAssertEqual(engine, 0)
        XCTAssertEqual(reload, 1)
    }

    func testFingerprintDiffersWhenArchiveStartChanges() {
        let url = URL(string: "https://example.invalid/index.m3u8")!
        let a = PlayableMedia(
            id: "catchup-timeshift-a",
            url: url,
            title: "A",
            subtitle: nil,
            posterURL: nil,
            kind: .vod,
            startTime: 0,
            contentRef: .live("stream"),
            archiveWindowStart: clipStart,
            archiveWindowEnd: clipEnd
        )
        let b = PlayableMedia(
            id: "catchup-timeshift-b",
            url: url,
            title: "A",
            subtitle: nil,
            posterURL: nil,
            kind: .vod,
            startTime: 0,
            contentRef: .live("stream"),
            archiveWindowStart: clipStart.addingTimeInterval(120),
            archiveWindowEnd: clipEnd
        )
        XCTAssertNotEqual(a.playbackSourceFingerprint, b.playbackSourceFingerprint)
    }

    func testIdenticalFingerprintIsDetectableSameSource() {
        let url = URL(string: "https://example.invalid/index.m3u8")!
        let a = PlayableMedia(
            id: "catchup-timeshift-a",
            url: url,
            title: "A",
            subtitle: nil,
            posterURL: nil,
            kind: .vod,
            startTime: 0,
            contentRef: .live("stream"),
            archiveWindowStart: clipStart,
            archiveWindowEnd: clipEnd
        )
        let b = PlayableMedia(
            id: "catchup-timeshift-b",
            url: url,
            title: "A",
            subtitle: nil,
            posterURL: nil,
            kind: .vod,
            startTime: 0,
            contentRef: .live("stream"),
            archiveWindowStart: clipStart,
            archiveWindowEnd: clipEnd
        )
        XCTAssertEqual(a.playbackSourceFingerprint, b.playbackSourceFingerprint)
    }
}
