# Build results

## Environment (this Cloud agent)

| Item | Value |
|---|---|
| Host OS | Linux (Cursor Cloud) |
| Xcode | **Not installed** |
| tvOS Simulator | **Unavailable** |
| Date | 2026-09-25 |

## Upstream pins used in this PR

See `LUME_UPSTREAM_COMMIT.txt` and `LUMEENGINE_UPSTREAM_COMMIT.txt`.

## Mac verification

**Pending** on a Mac with **Xcode 26.4+** and **tvOS 18** Simulator.

A Cursor private worker was visible (`MacBook-Air-M5`) but registered only for
`gennadii-TIME/juplite`, not TeamPlay — this agent could not target it for an
`xcodebuild` of this repository.

### Required Mac commands (for the reviewer / next Mac run)

```bash
# 1) Confirm toolchain
xcodebuild -version
xcrun simctl list devices available | grep -i 'apple tv'

# 2) Build TeamPlay (Lume scheme, TeamPlay display name)
xcodebuild build \
  -project Lume.xcodeproj -scheme Lume \
  -destination 'platform=tvOS Simulator,name=Apple TV 4K' \
  -clonedSourcePackagesDirPath ~/Library/Developer/Lume-SharedSPM \
  -derivedDataPath /tmp/teamplay-dd

# 3) Boot Simulator, run, screenshot About + Live TV + Player
```

Paste logs and screenshot paths below when complete.

### Results

- [ ] Upstream Lume builds on Apple TV Simulator
- [ ] TeamPlay (this tree) builds on Apple TV Simulator
- [ ] About shows TeamPlay
- [ ] User M3U → play → zap → back to catalog demonstrated
- [ ] Screenshots attached to PR
