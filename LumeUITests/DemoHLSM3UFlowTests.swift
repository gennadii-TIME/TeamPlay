import XCTest

/// Adds a small HLS m3u playlist through the add form, waits for the main
/// catalog, syncs it, then verifies Live TV can open a channel in the player.
///
/// Playlist URL resolves to `Fixtures/demo.m3u` served from the host
/// (`http://127.0.0.1:8766/demo.m3u`, reachable from the simulator) or the
/// same file on GitHub raw once pushed. The fixture lists one live row that
/// plays Apple's public bipbop HLS sample.
///
/// Local runs: `python3 -m http.server 8766 --bind 127.0.0.1` in
/// `LumeUITests/Fixtures`.
///
/// Launches under `-ui-testing` like the other flow tests: CloudKit is disabled
/// there, and auto-sync is skipped — import is triggered manually afterward.
final class DemoHLSM3UFlowTests: XCTestCase {
    private let playlistName = "Demo HLS"
    private let playlistURLCandidates = [
        "http://127.0.0.1:8766/demo.m3u",
        "https://raw.githubusercontent.com/gennadii-TIME/TeamPlay/cursor/demo-hls-m3u-ui-test-47ed/LumeUITests/Fixtures/demo.m3u",
    ]

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testAddDemoHLSPlaylistAndPlayLiveChannel() {
        let app = XCUIApplication()
        launchAndOpenAddForm(app)
        addDemoHLSPlaylist(app)
        waitForCatalogAfterAdd(app)
        activateDemoPlaylist(app)
        runManualSync(app)
        attemptPlayFirstLiveChannel(app)
    }

    // MARK: - Steps

    private func launchAndOpenAddForm(_ app: XCUIApplication) {
        app.launchArguments = ["-ui-testing"]
        app.launch()

        if app.tabBars.firstMatch.waitForExistence(timeout: 5) {
            XCTAssertTrue(app.openSettingsSheet(), "Settings sheet did not open")
            let addButton = app.buttons["Add Playlist"]
            XCTAssertTrue(addButton.waitForExistence(timeout: 10))
            addButton.tap()
        }
    }

    private func addDemoHLSPlaylist(_ app: XCUIApplication) {
        let m3uSegment = app.buttons["M3U"]
        XCTAssertTrue(m3uSegment.waitForExistence(timeout: 10), "No M3U segment.\n\(app.debugDescription)")
        m3uSegment.tap()

        let nameField = app.textFields["e.g. My IPTV"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 10))
        nameField.tap()
        nameField.typeText(playlistName)

        let urlField = app.textFields["e.g. http://example.com/playlist.m3u"]
        urlField.tap()
        urlField.typeText("\(resolvedPlaylistURL)\n")

        let submitCandidates = app.buttons.matching(identifier: "Add Playlist").allElementsBoundByIndex
        guard let addPlaylist = submitCandidates.last(where: { $0.isHittable && $0.isEnabled }) ?? submitCandidates.last else {
            return XCTFail("No Add Playlist button found")
        }
        if !addPlaylist.isHittable { app.swipeUp() }
        addPlaylist.tap()
    }

    /// Waits for validation to finish and the browse UI to replace the add form.
    private func waitForCatalogAfterAdd(_ app: XCUIApplication) {
        let urlField = app.textFields["e.g. http://example.com/playlist.m3u"]
        XCTAssertTrue(urlField.waitForNonExistence(timeout: 60), "Playlist was not accepted within 60s")

        if app.navigationBars["Settings"].waitForExistence(timeout: 3) {
            dismissSettingsToTabBar(app)
        }

        XCTAssertTrue(
            app.tabBars.firstMatch.waitForExistence(timeout: 60),
            "Catalog UI did not appear after adding the playlist.\n\(app.debugDescription)"
        )
    }

    private func dismissSettingsToTabBar(_ app: XCUIApplication) {
        let settingsNav = app.navigationBars["Settings"]
        if settingsNav.waitForExistence(timeout: 5) {
            let from = settingsNav.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            let target = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 1.0))
            from.press(forDuration: 0.1, thenDragTo: target)
            XCTAssertTrue(settingsNav.waitForNonExistence(timeout: 10), "Settings sheet did not dismiss")
        }
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 30), "Tab bar not visible")
    }

    private func activateDemoPlaylist(_ app: XCUIApplication) {
        app.tabBars.buttons["Live TV"].tap()
        let switcher = app.playlistSwitcher(named: "Test Playlist")
        XCTAssertTrue(switcher.waitForExistence(timeout: 20), "Playlist switcher not found")
        switcher.tap()
        let item = app.buttons[playlistName].firstMatch
        XCTAssertTrue(item.waitForExistence(timeout: 10), "Playlist switcher didn't list \(playlistName)")
        item.tap()
        let switchOverlay = app.staticTexts.matching(
            NSPredicate(format: "label BEGINSWITH %@", "Switching to")
        ).firstMatch
        if switchOverlay.waitForExistence(timeout: 5) {
            _ = switchOverlay.waitForNonExistence(timeout: 60)
        }
    }

    private func runManualSync(_ app: XCUIApplication) {
        let syncButton = app.syncToolbarButton
        XCTAssertTrue(syncButton.waitForExistence(timeout: 10), "Sync button not found")
        syncButton.tap()
        let startSync = app.buttons["Start Sync"]
        XCTAssertTrue(startSync.waitForExistence(timeout: 10), "Sync sheet didn't open")
        startSync.tap()
        let doneSync = app.buttons["Done"]
        XCTAssertTrue(doneSync.waitForExistence(timeout: 180), "Demo HLS sync did not complete")
        doneSync.tap()
    }

    private var resolvedPlaylistURL: String {
        for candidate in playlistURLCandidates {
            guard let probe = URL(string: candidate) else { continue }
            if let (_, response) = try? URLSession.shared.syncData(from: probe),
               (response as? HTTPURLResponse)?.statusCode == 200 {
                return candidate
            }
        }
        return playlistURLCandidates[0]
    }

    private func attemptPlayFirstLiveChannel(_ app: XCUIApplication) {
        app.tabBars.buttons["Live TV"].tap()

        if app.staticTexts["No Channels"].waitForExistence(timeout: 10) {
            return XCTFail("Live TV is empty after syncing Demo HLS.\n\(app.debugDescription)")
        }

        let channel = app.scrollViews.firstMatch.buttons.firstMatch
        XCTAssertTrue(channel.waitForExistence(timeout: 60), "No channel row to play.\n\(app.debugDescription)")
        channel.tap()

        XCTAssertTrue(
            waitForPlayablePlayerChrome(app, timeout: 60),
            "Player did not show playable controls.\n\(app.debugDescription)"
        )

        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Demo-HLS-playback"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func waitForPlayablePlayerChrome(_ app: XCUIApplication, timeout: TimeInterval) -> Bool {
        let controls = [
            app.buttons["Close player"],
            app.buttons["Pause"],
            app.buttons["Play"],
        ]
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if controls.contains(where: { $0.exists && $0.isHittable }) { return true }
            RunLoop.current.run(until: Date().addingTimeInterval(0.25))
        }
        return controls.contains(where: \.exists)
    }
}

private extension URLSession {
    func syncData(from url: URL) throws -> (Data, URLResponse) {
        var result: (Data, URLResponse)?
        var error: Error?
        let semaphore = DispatchSemaphore(value: 0)
        let task = dataTask(with: url) { data, response, err in
            if let data, let response {
                result = (data, response)
            }
            error = err
            semaphore.signal()
        }
        task.resume()
        semaphore.wait()
        if let error { throw error }
        return result!
    }
}
