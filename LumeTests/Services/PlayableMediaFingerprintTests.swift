//
//  PlayableMediaFingerprintTests.swift
//  LumeTests
//
//  Playback-source fingerprint must change when URL or archive bounds change,
//  so switchMedia replaces media even if the catchup id string collides.
//

import XCTest
@testable import Lume

final class PlayableMediaFingerprintTests: XCTestCase {
    func testFingerprintChangesWhenArchiveBoundsChange() throws {
        let url = try XCTUnwrap(URL(string: "https://example.test/archive.m3u8"))
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let a = PlayableMedia(
            id: "catchup-timeshift-ch-1700000000",
            url: url,
            title: "Ch",
            subtitle: nil,
            posterURL: nil,
            kind: .vod,
            startTime: 0,
            contentRef: .live("ch"),
            archiveWindowStart: start,
            archiveWindowEnd: start.addingTimeInterval(120)
        )
        let b = PlayableMedia(
            id: "catchup-timeshift-ch-1700000000",
            url: url,
            title: "Ch",
            subtitle: nil,
            posterURL: nil,
            kind: .vod,
            startTime: 0,
            contentRef: .live("ch"),
            archiveWindowStart: start,
            archiveWindowEnd: start.addingTimeInterval(600)
        )
        XCTAssertEqual(a.id, b.id)
        XCTAssertNotEqual(a.playbackSourceFingerprint, b.playbackSourceFingerprint)
    }

    func testFingerprintChangesWhenURLChanges() throws {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let end = start.addingTimeInterval(120)
        let a = PlayableMedia(
            id: "catchup-timeshift-ch-1700000000",
            url: try XCTUnwrap(URL(string: "https://example.test/a.m3u8")),
            title: "Ch",
            subtitle: nil,
            posterURL: nil,
            kind: .vod,
            startTime: 0,
            contentRef: .live("ch"),
            archiveWindowStart: start,
            archiveWindowEnd: end
        )
        let b = PlayableMedia(
            id: "catchup-timeshift-ch-1700000000",
            url: try XCTUnwrap(URL(string: "https://example.test/b.m3u8")),
            title: "Ch",
            subtitle: nil,
            posterURL: nil,
            kind: .vod,
            startTime: 0,
            contentRef: .live("ch"),
            archiveWindowStart: start,
            archiveWindowEnd: end
        )
        XCTAssertNotEqual(a.playbackSourceFingerprint, b.playbackSourceFingerprint)
    }

    func testIdenticalSourceSameFingerprint() throws {
        let url = try XCTUnwrap(URL(string: "https://example.test/archive.m3u8"))
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let end = start.addingTimeInterval(120)
        let a = PlayableMedia(
            id: "x",
            url: url,
            title: "Ch",
            subtitle: nil,
            posterURL: nil,
            kind: .vod,
            startTime: 0,
            contentRef: .live("ch"),
            archiveWindowStart: start,
            archiveWindowEnd: end
        )
        let b = PlayableMedia(
            id: "y",
            url: url,
            title: "Other title",
            subtitle: nil,
            posterURL: nil,
            kind: .vod,
            startTime: 0,
            contentRef: .live("ch"),
            archiveWindowStart: start,
            archiveWindowEnd: end
        )
        XCTAssertEqual(a.playbackSourceFingerprint, b.playbackSourceFingerprint)
    }
}
