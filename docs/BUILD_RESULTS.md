# Build results — multi-platform matrix (PR #6)

Branch: `cursor/teamplay-lume-base-8341` · Draft [PR #6](https://github.com/gennadii-TIME/TeamPlay/pull/6)  
PR #4 stays unmerged.

## Latest attempt (2026-09-25)

| Item | Value |
|---|---|
| This agent host | **Linux** managed Cloud (`runtime=managed`, `uname=Linux`) |
| `xcodebuild` | **Not found** |
| Private worker **TeamPlay-Mac** | **Online**, idle, repo `gennadii-TIME/TeamPlay`, `eligibleForSubagent=true`, workerId `34fc848e-2a8e-4863-8a1b-4b5b64525185` |
| Placement | Cloud/Task subagents from this run were **not** scheduled onto TeamPlay-Mac (landed on managed Linux again: [bc-dcfecddc](bc-dcfecddc-0431-59e9-a2c4-73b074d5cf99), [bc-ba7a3169](bc-ba7a3169-0299-5f61-92aa-d43f8980cb88)) |

**Blocker:** this conversation runs on managed Linux and cannot relocate itself to TeamPlay-Mac. Builds/screenshots require a **new agent run started on TeamPlay-Mac** (private worker), or manual Cursor Desktop on that Mac.

### How to unblock

1. In Cursor, start a Cloud Agent / worker session **on TeamPlay-Mac** (not managed public cloud).
2. Checkout `cursor/teamplay-lume-base-8341`, merge `main`, run:

```bash
xcodebuild -version
xcodebuild -showsdks
xcrun simctl list devices available
./Scripts/build-all-platforms.sh
```

3. Fix failures, fill this file’s matrix, attach screenshots to PR #6, keep PR draft, do not merge.

See also `docs/MAC_VERIFICATION.md`.

## Upstream pins

See `LUME_UPSTREAM_COMMIT.txt` / `LUMEENGINE_UPSTREAM_COMMIT.txt`.

## Declared platforms (`Lume.xcodeproj`)

`SUPPORTED_PLATFORMS = appletvos appletvsimulator iphoneos iphonesimulator macosx xros xrsimulator`  
Deployment: **iOS/tvOS 18**, **macOS 15**, **visionOS 2** · **Xcode 26.4+** required.

## Mac toolchain (fill on TeamPlay-Mac)

| Item | Value |
|---|---|
| `xcodebuild -version` | _pending — run on TeamPlay-Mac_ |
| SDKs | _pending_ |
| Simulators (TV / iPhone / iPad / Vision) | _pending_ |

## Matrix (fill on TeamPlay-Mac)

| Platform | Build | Add M3U | Play | Screenshot |
|---|---|---|---|---|
| Apple TV (tvOS 18) | ☐ | ☐ | ☐ (+ zap / back) | ☐ |
| iPhone (iOS 18) | ☐ | ☐ | ☐ | ☐ |
| iPad (iPadOS 18) | ☐ | ☐ | ☐ | ☐ |
| Mac (macOS 15) | ☐ | ☐ | ☐ | ☐ |
| Vision Pro (visionOS 2) | ☐ | ☐ | ☐ | ☐ |

### Logs / screenshots

_Pending TeamPlay-Mac run._
