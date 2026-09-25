# TeamPlay

IPTV player for **Apple TV**, based on the full [Lume](https://github.com/bilipp/Lume) codebase (AGPL-3.0), with TeamPlay branding.

Canonical product plan: [`docs/PRODUCT_PLAN.md`](docs/PRODUCT_PLAN.md).

> **PR #4** (parser-only prototype) is **not** this approach and must **not** be merged. This branch vendors Lume + LumeEngine as the real foundation.

## Build requirements (required change vs early drafts)

| Tool / platform | Required |
|---|---|
| **Xcode** | **26.4 or later** (iOS 26 SDK) |
| **tvOS deployment** | **18.0+** |
| **iOS / iPadOS** | 18.0+ |
| **macOS** | 15.0+ |
| Disk for SPM | Plan ~6+ GB for KSPlayer/VLCKit package clones |

Do **not** use Xcode 16 / tvOS 17 targets with this tree — upstream Lume does not support them.

Pinned upstream commits: see [`docs/LUME_UPSTREAM_COMMIT.txt`](docs/LUME_UPSTREAM_COMMIT.txt) and [`docs/LUMEENGINE_UPSTREAM_COMMIT.txt`](docs/LUMEENGINE_UPSTREAM_COMMIT.txt). Details: [`docs/BUILD_REQUIREMENTS.md`](docs/BUILD_REQUIREMENTS.md).

## Open & run (Mac)

```bash
# LumeEngine is vendored at ./LumeEngine (local SPM path in the Xcode project)
open Lume.xcodeproj
```

1. Scheme **Lume** (product display name **TeamPlay**)
2. Destination: **Apple TV** / Apple TV 4K Simulator (tvOS 18+)
3. Build & run (`⌘R`)
4. Add your own M3U / Xtream credentials (no bundled content)

Shared SPM cache (recommended):

```bash
xcodebuild build \
  -project Lume.xcodeproj -scheme Lume \
  -destination 'platform=tvOS Simulator,name=Apple TV 4K' \
  -clonedSourcePackagesDirPath ~/Library/Developer/Lume-SharedSPM
```

## What this PR keeps from Lume

- Playlist import / sync (M3U, Xtream, and other sources Lume supports)
- Playback engines (KSPlayer → VLCKit → AVPlayer → LumeEngine)
- tvOS navigation, Live TV, EPG, and archive/catch-up where the source supports them

## Branding (first pass)

- Display name / About: **TeamPlay**
- Bundle ID: `time.teamplay.app`
- Source / license links point at this repository (AGPL)
- UI/UX customization continues in follow-up PRs — do not copy Lume’s look 1:1 long-term

## License

AGPL-3.0. TeamPlay includes Lume and LumeEngine; corresponding source must remain available under AGPL. See [`NOTICE`](NOTICE).
