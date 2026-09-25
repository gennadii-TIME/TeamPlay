# Build results — multi-platform matrix

## Cloud agent (this run)

| Item | Value |
|---|---|
| Host | Linux Cursor Cloud |
| Xcode / Simulators | **Unavailable** |
| Date | 2026-09-25 |

Private Mac worker `MacBook-Air-M5` was online but registered only for
`gennadii-TIME/juplite`, not TeamPlay — not usable for this repo’s `xcodebuild`.

## Upstream pins

See `LUME_UPSTREAM_COMMIT.txt` / `LUMEENGINE_UPSTREAM_COMMIT.txt`.

## Xcode project platforms (from `Lume.xcodeproj`)

`SUPPORTED_PLATFORMS = appletvos appletvsimulator iphoneos iphonesimulator macosx xros xrsimulator`  
`TARGETED_DEVICE_FAMILY = 1,2,3,7`  
Deployment: iOS 18 / tvOS 18 / macOS 15 / visionOS 2 — matches PRODUCT_PLAN.

## Mac verification checklist (reviewer or Mac worker)

Run `Scripts/build-all-platforms.sh` then manual playback on each destination.

| Platform | Build | Add M3U | Play | Screenshot |
|---|---|---|---|---|
| Apple TV (tvOS 18) | ☐ | ☐ | ☐ (+ zap / back) | ☐ |
| iPhone (iOS 18) | ☐ | ☐ | ☐ | ☐ |
| iPad (iPadOS 18) | ☐ | ☐ | ☐ | ☐ |
| Mac (macOS 15) | ☐ | ☐ | ☐ | ☐ |
| Vision Pro (visionOS 2) | ☐ | ☐ | ☐ | ☐ |

Paste `xcodebuild -version`, log tails from `docs/build-logs/`, and screenshot
paths below when complete.

### Logs / screenshots

_Pending Mac run._

## PR #4

Draft PR #4 remains a parser-only prototype and **must not be merged**.
