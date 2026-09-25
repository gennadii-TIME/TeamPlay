# Build results — multi-platform matrix (PR #6)

Branch: `cursor/teamplay-lume-base-8341` · Draft [PR #6](https://github.com/gennadii-TIME/TeamPlay/pull/6)  
PR #4 stays unmerged (parser-only; does not meet PRODUCT_PLAN).

## Cloud / this agent

| Item | Value |
|---|---|
| Host | **Linux** Cursor Cloud (`uname`: Linux x86_64) |
| `xcodebuild` | **Not found** |
| Simulators | **Unavailable** |
| Date | 2026-09-25 |

**Blocker:** this environment cannot compile or run Apple platforms. Verification must happen in **Cursor on your Mac** (or a private Mac worker that includes the TeamPlay repo — currently the online worker is only registered for `juplite`).

## Upstream pins

See `LUME_UPSTREAM_COMMIT.txt` / `LUMEENGINE_UPSTREAM_COMMIT.txt`.

## Xcode project platforms (declared)

`SUPPORTED_PLATFORMS = appletvos appletvsimulator iphoneos iphonesimulator macosx xros xrsimulator`  
`TARGETED_DEVICE_FAMILY = 1,2,3,7`  
Deployment: **iOS/tvOS 18**, **macOS 15**, **visionOS 2** · requires **Xcode 26.4+**

## Mac steps (Cursor on Mac — fill this section)

```bash
cd /path/to/TeamPlay
git fetch origin
git checkout cursor/teamplay-lume-base-8341
git pull origin cursor/teamplay-lume-base-8341
git merge origin/main   # keep PRODUCT_PLAN current

xcodebuild -version
xcodebuild -showsdks
xcrun simctl list devices available

./Scripts/build-all-platforms.sh
```

If Xcode **&lt; 26.4**, record the installed version here and stop — do not claim success.

### Toolchain observed on Mac

| Item | Value |
|---|---|
| `xcodebuild -version` | _pending_ |
| SDKs present | _pending_ |
| Apple TV / iPhone / iPad / Vision simulators | _pending_ |

### Matrix

| Platform | Build | Add M3U | Play | Screenshot |
|---|---|---|---|---|
| Apple TV (tvOS 18) | ☐ | ☐ | ☐ (+ zap / back) | ☐ |
| iPhone (iOS 18) | ☐ | ☐ | ☐ | ☐ |
| iPad (iPadOS 18) | ☐ | ☐ | ☐ | ☐ |
| Mac (macOS 15) | ☐ | ☐ | ☐ | ☐ |
| Vision Pro (visionOS 2) | ☐ | ☐ | ☐ | ☐ |

### Logs / screenshots

- Build logs: `docs/build-logs/` (from `Scripts/build-all-platforms.sh`)
- Attach Simulator/device screenshots to PR #6; keep the PR **draft** until this matrix is filled.

## Related

- Feature #5 (commercial mute) is **after** this foundation PR — separate PR once builds are green.
- PR #4: do not merge.
