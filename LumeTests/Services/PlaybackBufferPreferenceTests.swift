import XCTest
@testable import Lume

final class PlaybackBufferPreferenceTests: XCTestCase {
    private var defaults: UserDefaults!
    private let suiteName = "PlaybackBufferPreferenceTests.\(UUID().uuidString)"

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        super.tearDown()
    }

    func testDefaultIsAutomaticAndPersistsRawValue() {
        XCTAssertEqual(PlayerSettings.PlaybackBufferPreference.default, .automatic)
        XCTAssertNil(PlayerSettings.PlaybackBufferPreference.automatic.seconds)

        defaults.set(PlayerSettings.PlaybackBufferPreference.fiveSeconds.rawValue,
                     forKey: PlayerSettings.PlaybackBufferPreference.storageKey)
        let resolved = PlayerSettings.PlaybackBufferPreference.resolve(
            raw: defaults.string(forKey: PlayerSettings.PlaybackBufferPreference.storageKey)
        )
        XCTAssertEqual(resolved, .fiveSeconds)
        XCTAssertEqual(resolved.seconds, 5)
    }

    func testAutomaticReturnsEngineDefaults() {
        let seconds = PlayerSettings.PlaybackBufferPreference.forwardBufferSeconds(
            isLive: true,
            automaticLive: 4,
            automaticVOD: 8,
            defaults: defaults
        )
        XCTAssertEqual(seconds, 4)

        let vod = PlayerSettings.PlaybackBufferPreference.forwardBufferSeconds(
            isLive: false,
            automaticLive: 4,
            automaticVOD: 8,
            defaults: defaults
        )
        XCTAssertEqual(vod, 8)
    }

    func testManualOverridesLiveAndVODAlike() {
        defaults.set(PlayerSettings.PlaybackBufferPreference.tenSeconds.rawValue,
                     forKey: PlayerSettings.PlaybackBufferPreference.storageKey)
        let live = PlayerSettings.PlaybackBufferPreference.forwardBufferSeconds(
            isLive: true, automaticLive: 4, automaticVOD: 8, defaults: defaults
        )
        let vod = PlayerSettings.PlaybackBufferPreference.forwardBufferSeconds(
            isLive: false, automaticLive: 4, automaticVOD: 8, defaults: defaults
        )
        XCTAssertEqual(live, 10)
        XCTAssertEqual(vod, 10)
    }

    func testVLCMillisecondsMapping() {
        defaults.set(PlayerSettings.PlaybackBufferPreference.threeSeconds.rawValue,
                     forKey: PlayerSettings.PlaybackBufferPreference.storageKey)
        let ms = PlayerSettings.PlaybackBufferPreference.vlcCachingMilliseconds(
            isLive: true, automaticLiveMs: 3000, automaticVODMs: 1500, defaults: defaults
        )
        XCTAssertEqual(ms, 3000)

        defaults.removeObject(forKey: PlayerSettings.PlaybackBufferPreference.storageKey)
        let auto = PlayerSettings.PlaybackBufferPreference.vlcCachingMilliseconds(
            isLive: false, automaticLiveMs: 3000, automaticVODMs: 1500, defaults: defaults
        )
        XCTAssertEqual(auto, 1500)
    }
}
