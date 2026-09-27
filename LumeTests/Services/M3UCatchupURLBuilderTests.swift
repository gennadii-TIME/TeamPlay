//
//  M3UCatchupURLBuilderTests.swift
//  LumeTests
//

import Foundation
@testable import Lume
import Testing

struct M3UCatchupURLBuilderTests {
    private let start = Date(timeIntervalSince1970: 1_700_000_000)
    private var end: Date { start.addingTimeInterval(3600) }

    // MARK: - Capability

    @Test func `known shift scheme advertises archive`() {
        let cap = M3UCatchupURLBuilder.capability(catchup: "shift", catchupSource: nil, catchupDays: 7)
        #expect(cap.hasArchive)
        #expect(cap.days == 7)
        #expect(cap.mode == "shift")
        #expect(cap.source == nil)
    }

    @Test func `append without source does not advertise archive`() {
        let cap = M3UCatchupURLBuilder.capability(catchup: "append", catchupSource: nil, catchupDays: 7)
        #expect(!cap.hasArchive)
        #expect(cap.mode == nil)
    }

    @Test func `unknown scheme does not advertise archive`() {
        let cap = M3UCatchupURLBuilder.capability(
            catchup: "acme-private",
            catchupSource: "http://example.com/x",
            catchupDays: 7
        )
        #expect(!cap.hasArchive)
    }

    @Test func `disabled catchup clears capability`() {
        let cap = M3UCatchupURLBuilder.capability(catchup: "disabled", catchupSource: nil, catchupDays: 7)
        #expect(!cap.hasArchive)
    }

    @Test func `tvg-rec days without type infer flussonic for mono m3u8`() {
        let cap = M3UCatchupURLBuilder.capability(
            catchup: nil,
            catchupSource: nil,
            catchupDays: 7,
            streamURL: "http://cdn.example.com/ch001/mono.m3u8?token=abc"
        )
        #expect(cap.hasArchive)
        #expect(cap.mode == "flussonic")
        #expect(cap.days == 7)
    }

    @Test func `tvg-rec zero without type does not advertise archive`() {
        let cap = M3UCatchupURLBuilder.capability(
            catchup: nil,
            catchupSource: nil,
            catchupDays: 0,
            streamURL: "http://cdn.example.com/ch001/mono.m3u8?token=abc"
        )
        #expect(!cap.hasArchive)
    }

    @Test func `tvg-rec days without flussonic path does not invent scheme`() {
        let cap = M3UCatchupURLBuilder.capability(
            catchup: nil,
            catchupSource: nil,
            catchupDays: 7,
            streamURL: "http://cdn.example.com/dash/stream.mpd?token=abc"
        )
        #expect(!cap.hasArchive)
    }

    @Test func `inferred flussonic preserves query token in built url`() throws {
        let url = try #require(M3UCatchupURLBuilder.build(
            streamURL: "http://cdn.example.com/ch001/mono.m3u8?token=abc",
            mode: "flussonic",
            source: nil,
            start: start,
            end: end
        ))
        #expect(url.absoluteString == "http://cdn.example.com/ch001/mono-1700000000-3600.m3u8?token=abc")
    }

    // MARK: - Handlers

    @Test func `shift appends utc query`() throws {
        let url = try #require(M3UCatchupURLBuilder.build(
            streamURL: "http://example.com/live/a.ts",
            mode: "shift",
            source: nil,
            start: start,
            end: end
        ))
        #expect(url.absoluteString == "http://example.com/live/a.ts?utc=1700000000&lutc=1700003600")
    }

    @Test func `shift uses ampersand when query exists`() throws {
        let url = try #require(M3UCatchupURLBuilder.build(
            streamURL: "http://example.com/live/a.ts?token=1",
            mode: "shift",
            source: nil,
            start: start,
            end: end
        ))
        #expect(url.absoluteString == "http://example.com/live/a.ts?token=1&utc=1700000000&lutc=1700003600")
    }

    @Test func `default without source matches shift`() throws {
        let url = try #require(M3UCatchupURLBuilder.build(
            streamURL: "http://example.com/live/a.ts",
            mode: "default",
            source: nil,
            start: start,
            end: end
        ))
        #expect(url.absoluteString.contains("utc=1700000000"))
        #expect(url.absoluteString.contains("lutc=1700003600"))
    }

    @Test func `default with source substitutes template`() throws {
        let url = try #require(M3UCatchupURLBuilder.build(
            streamURL: "http://example.com/live/a.ts",
            mode: "default",
            source: "?utc=${start}&lutc=${end}",
            start: start,
            end: end
        ))
        #expect(url.absoluteString == "http://example.com/live/a.ts?utc=1700000000&lutc=1700003600")
    }

    @Test func `append absolute template replaces live url`() throws {
        let url = try #require(M3UCatchupURLBuilder.build(
            streamURL: "http://example.com/live/a.ts",
            mode: "append",
            source: "http://example.com/archive/ch1?from={utc}&to={lutc}",
            start: start,
            end: end
        ))
        #expect(url.absoluteString == "http://example.com/archive/ch1?from=1700000000&to=1700003600")
    }

    @Test func `flussonic inserts utc duration before extension`() throws {
        let url = try #require(M3UCatchupURLBuilder.build(
            streamURL: "http://example.com/ch/index.m3u8",
            mode: "flussonic",
            source: nil,
            start: start,
            end: end
        ))
        #expect(url.absoluteString == "http://example.com/ch/index-1700000000-3600.m3u8")
    }

    @Test func `flussonic-ts builds timeshift_abs path`() throws {
        let url = try #require(M3UCatchupURLBuilder.build(
            streamURL: "http://example.com/ch/index.m3u8",
            mode: "flussonic-ts",
            source: nil,
            start: start,
            end: end
        ))
        #expect(url.absoluteString == "http://example.com/ch/timeshift_abs-1700000000.ts")
    }

    @Test func `xtream transforms live path to timeshift`() throws {
        let url = try #require(M3UCatchupURLBuilder.build(
            streamURL: "http://cdn.example.com:8080/live/user/pass/4242.ts",
            mode: "xtream",
            source: nil,
            start: start,
            end: end
        ))
        #expect(url.absoluteString.hasPrefix("http://cdn.example.com:8080/timeshift/user/pass/60/"))
        #expect(url.absoluteString.hasSuffix("/4242.ts"))
        // Start is formatted in UTC.
        #expect(url.absoluteString.contains("/2023-11-14:22-13/"))
    }

    @Test func `unknown mode returns nil`() {
        let url = M3UCatchupURLBuilder.build(
            streamURL: "http://example.com/live/a.ts",
            mode: "acme-private",
            source: "http://example.com/x",
            start: start,
            end: end
        )
        #expect(url == nil)
    }

    @Test func `fixture playlist parses supported and rejected schemes`() async throws {
        let fileURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/m3u-catchup-schemes.m3u")
        #expect(FileManager.default.fileExists(atPath: fileURL.path))

        var entries: [M3UEntry] = []
        try await M3UParser.parseStreaming(fileURL: fileURL) { _ in } onBatch: { batch, _ in
            entries.append(contentsOf: batch)
        }
        #expect(entries.count == 9)

        let byId = Dictionary(uniqueKeysWithValues: entries.compactMap { entry in
            entry.tvgId.map { ($0, entry) }
        })

        let shift = M3UCatchupURLBuilder.capability(
            catchup: byId["shift.1"]?.catchup,
            catchupSource: byId["shift.1"]?.catchupSource,
            catchupDays: byId["shift.1"]?.catchupDays
        )
        #expect(shift.hasArchive)

        let flussonic = M3UCatchupURLBuilder.capability(
            catchup: byId["fs.1"]?.catchup,
            catchupSource: byId["fs.1"]?.catchupSource,
            catchupDays: byId["fs.1"]?.catchupDays
        )
        #expect(flussonic.mode == "flussonic")

        let unknown = M3UCatchupURLBuilder.capability(
            catchup: byId["unknown.1"]?.catchup,
            catchupSource: byId["unknown.1"]?.catchupSource,
            catchupDays: byId["unknown.1"]?.catchupDays
        )
        #expect(!unknown.hasArchive)

        let appendBad = M3UCatchupURLBuilder.capability(
            catchup: byId["append.bad"]?.catchup,
            catchupSource: byId["append.bad"]?.catchupSource,
            catchupDays: byId["append.bad"]?.catchupDays
        )
        #expect(!appendBad.hasArchive)
    }
}