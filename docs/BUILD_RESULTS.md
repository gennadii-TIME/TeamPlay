# Build results — multi-platform matrix (PR #6)

Branch: `cursor/teamplay-lume-base-8341` · Draft [PR #6](https://github.com/gennadii-TIME/TeamPlay/pull/6)  
PR #4 stays unmerged.

## Verification host (2026-09-25)

| Item | Value |
|---|---|
| Host | **TeamPlay-Mac** (`uname`: Darwin 25.6.0 arm64, MacBook-Air-M5) |
| `xcodebuild -version` | **Xcode 27.0** (Build 27A266a) — meets Xcode 26.4+ requirement |
| Shared SPM | `~/Library/Developer/Lume-SharedSPM` |
| DerivedData | `/tmp/teamplay-dd-all` |
| Local signing team used for device/mac builds | `7Q4F885549` (Tinika Ltd) via `TEAMPLAY_DEVELOPMENT_TEAM` |

### SDKs present

iOS/tvOS/macOS/visionOS **27.0** (device + simulator). See `docs/build-logs/xcode-sdks.txt`.

### Simulator runtimes installed on this Mac

| Runtime | Status |
|---|---|
| iOS 26.5 | Installed (used for iPhone / iPad) |
| tvOS 27.0 | Downloaded + installed during this run |
| visionOS 27.0 | Downloaded + installed during this run |

Also installed missing **Metal Toolchain** (`xcodebuild -downloadComponent MetalToolchain`) — required for KSPlayer `.metal` shaders.

## Upstream pins

See `LUME_UPSTREAM_COMMIT.txt` / `LUMEENGINE_UPSTREAM_COMMIT.txt`.

## Declared platforms (`Lume.xcodeproj`)

`SUPPORTED_PLATFORMS = appletvos appletvsimulator iphoneos iphonesimulator macosx xros xrsimulator`  
Deployment: **iOS/tvOS 18**, **macOS 15**, **visionOS 2**

## Matrix

| Platform | Build | Add M3U | Play | Screenshot |
|---|---|---|---|---|
| Apple TV (tvOS Simulator 27 / Apple TV 4K 3rd gen) | ✅ | ⚠ launch OK; full M3U UI flow not automated on tvOS this run | ⚠ | ✅ `docs/screenshots/tvos_launch.jpg` |
| iPhone (iOS Simulator 26.5 / iPhone 17 Pro) | ✅ | ✅ UI test `DemoHLSM3UFlowTests` | ✅ same UI test opens Live TV + player | ✅ `docs/screenshots/iphone_add_playlist.png`, `iphone_home.png` |
| iPad (iPadOS / iPad Pro 13-inch M5) | ✅ | ⚠ launch OK; iPad UI-test runner hit sim launch denial under load | ⚠ | ✅ `docs/screenshots/ipad_launch.png` |
| Mac (macOS 27) | ✅ | ⚠ app launches with `-ui-testing` (CloudKit skip); Screen Recording permission blocked window screenshots from this agent | ⚠ | ⚠ see limitations |
| Vision Pro (visionOS Simulator 27) | ✅ | ⚠ launch OK | ⚠ | ✅ `docs/screenshots/visionos_launch.jpg` |

### How builds were run

```bash
# After installing MetalToolchain + tvOS/visionOS runtimes:
export TEAMPLAY_DEVELOPMENT_TEAM=7Q4F885549
export TEAMPLAY_MACOS_ENTITLEMENTS="$PWD/Scripts/macos-local-entitlements.plist"
./Scripts/build-all-platforms.sh
```

macOS needs the sandbox-only entitlements override because the checked-in `Lume.entitlements` still references upstream `iCloud.bilipp.Lume` (release-compliance item; not fixed in this build pass). Without that override, or without `-ui-testing`, the Mac binary traps in `CKContainer(identifier:)`.

### M3U / playback evidence (iPhone)

- Fixture: `LumeUITests/Fixtures/demo.m3u` (Apple public bipbop HLS sample — legal test media).
- Command (local HTTP on `:8766`):

```bash
cd LumeUITests/Fixtures && python3 -m http.server 8766 --bind 127.0.0.1
xcodebuild test -project Lume.xcodeproj -scheme Lume \
  -clonedSourcePackagesDirPath ~/Library/Developer/Lume-SharedSPM \
  -derivedDataPath /tmp/teamplay-dd-uitest \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:LumeUITests/DemoHLSM3UFlowTests/testAddDemoHLSPlaylistAndPlayLiveChannel \
  -allowProvisioningUpdates DEVELOPMENT_TEAM=7Q4F885549
```

- Result: **`TEST SUCCEEDED`** (~62 s). Log: `docs/build-logs/uitest-iphone-m3u.log`.

### visionOS compile fixes landed in this branch

- `AirPlayRouteButton` / `AVPlayerCoordinator`: APIs unavailable on visionOS.
- `PremiumManager.purchase`: use `purchase(confirmIn:)` on visionOS.
- `LumeEngineCoordinator`: PiP bridge only on iOS/macOS/tvOS.
- `GlassEffectCompat`: material fallback on visionOS (`Glass` / `glassEffect` unavailable).
- `MovieDetailView` toolbar: include visionOS in the iOS toolbar branch.

### Logs / screenshots

- Build logs: `docs/build-logs/build-{tvOS,iPhone,iPad,macOS,visionOS}.log`
- Toolchain dumps: `docs/build-logs/xcode-version.txt`, `xcode-sdks.txt`, `sim-runtimes.txt`
- Screenshots: `docs/screenshots/`

## Limitations / follow-ups (not blocking the five-platform compile green)

1. **Simulator.app GUI** is not present in this Xcode install path; interaction used `simctl` + XCUITest. Window screenshots on Mac need Screen Recording permission for the agent terminal.
2. **iPad / tvOS / visionOS / Mac** M3U+play matrix cells are only partially filled (launch + iPhone E2E). Extend the UI test destinations next.
3. Release compliance from `docs/RELEASE_COMPLIANCE.md` / issue #7 (StoreKit products, branding, licenses) remains separate work — priority here was prototype builds.
4. Keep PR #6 **draft**. Do **not** merge PR #4.

## Related

- Issue #7 / `docs/RELEASE_COMPLIANCE.md` — licenses, branding, payments after builds.
- Feature #5 (commercial mute) is after this foundation PR.
