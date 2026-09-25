# Build requirements — Lume-based TeamPlay (all Apple platforms)

First PR scope (PRODUCT_PLAN): **one** Lume-based tree that builds for

| Platform | Deployment | Device family |
|---|---|---|
| Apple TV | **tvOS 18.0+** | 3 |
| iPhone / iPad | **iOS / iPadOS 18.0+** | 1, 2 |
| Mac | **macOS 15.0+** | — |
| Vision Pro | **visionOS 2.0+** | 7 |

## Toolchain

| Tool | Required |
|---|---|
| **Xcode** | **26.4 or later** (iOS 26 SDK) |
| Disk for SPM | ~6+ GB shared clone recommended (`~/Library/Developer/Lume-SharedSPM`) |

Do **not** claim Xcode 16 / tvOS 17 for this tree.

## Upstream pins

| Component | File |
|---|---|
| Lume | `docs/LUME_UPSTREAM_COMMIT.txt` |
| LumeEngine | `docs/LUMEENGINE_UPSTREAM_COMMIT.txt` |

Engine is vendored at `./LumeEngine` (Xcode local package path).

## Multi-platform build (Mac)

```bash
chmod +x Scripts/build-all-platforms.sh
./Scripts/build-all-platforms.sh
```

Or per destination with scheme `Lume` (display name **TeamPlay**):

```bash
SPM=(-clonedSourcePackagesDirPath ~/Library/Developer/Lume-SharedSPM)
DD=(-derivedDataPath /tmp/teamplay-dd)

xcodebuild build -project Lume.xcodeproj -scheme Lume "${SPM[@]}" "${DD[@]}" \
  -destination 'platform=tvOS Simulator,name=Apple TV 4K'
# …repeat for iPhone, iPad, macOS, visionOS Simulator
```

## Acceptance for PR #1 (platform matrix)

For **each** of tvOS, iPhone, iPad, Mac, Vision Pro:

1. App builds and launches  
2. User can add their own M3U  
3. Channel plays  
4. Screenshot of the UI attached  
5. On Apple TV: remote channel zap + return to catalog  

PR #4 (parser-only) does **not** meet this bar and must stay unmerged.

## Cloud limitation

Linux Cloud agents cannot run these builds. A Mac with Xcode 26.4+ (or a private worker that includes the **TeamPlay** repo) is required. Record outcomes in `docs/BUILD_RESULTS.md`.
