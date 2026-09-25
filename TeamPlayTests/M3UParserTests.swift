import Foundation
import XCTest
@testable import TeamPlay

final class M3UParserTests: XCTestCase {
    func testParsesExtendedEntriesAndGroups() {
        let text = """
        #EXTM3U url-tvg="https://example.com/epg.xml"
        #EXTINF:-1 tvg-id="ch1" tvg-logo="https://logo/1.png" group-title="News",CNN
        https://cdn.example/cnn.m3u8
        #EXTINF:-1 catchup="default" catchup-days="3" group-title="News",CNN Replayable
        https://cdn.example/cnn-archive.m3u8
        #EXTINF:-1 group-title="Movies" type="movie",Some Film
        https://cdn.example/movie.mp4
        """

        let result = M3UParser.parse(text: text)
        XCTAssertEqual(result.header?.epgURL, "https://example.com/epg.xml")
        XCTAssertEqual(result.entries.count, 3)
        XCTAssertEqual(result.entries[0].name, "CNN")
        XCTAssertEqual(result.entries[0].group, "News")

        let archive = M3UParser.archiveCapability(for: result.entries[1])
        XCTAssertTrue(archive.supported)
        XCTAssertEqual(archive.durationHours, 72)

        let noArchive = M3UParser.archiveCapability(for: result.entries[0])
        XCTAssertFalse(noArchive.supported)
    }

    func testArchiveRequiresPositiveWindow() {
        var entry = M3UEntry(
            name: "X",
            url: "https://x",
            tvgId: nil,
            logo: nil,
            group: nil,
            type: nil,
            catchup: "default",
            catchupDays: nil
        )
        XCTAssertFalse(M3UParser.archiveCapability(for: entry).supported)

        entry.catchupDays = 7
        XCTAssertTrue(M3UParser.archiveCapability(for: entry).supported)
        XCTAssertEqual(M3UParser.archiveCapability(for: entry).durationHours, 168)
    }

    func testFixtureFile() throws {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/sample_archive.m3u")
        let text = try String(contentsOf: url, encoding: .utf8)
        let result = M3UParser.parse(text: text)
        XCTAssertEqual(result.entries.count, 3)
        XCTAssertFalse(M3UParser.archiveCapability(for: result.entries[0]).supported)
        XCTAssertTrue(M3UParser.archiveCapability(for: result.entries[1]).supported)
    }
}
