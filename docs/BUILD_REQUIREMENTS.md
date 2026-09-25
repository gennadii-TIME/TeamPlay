# Build requirements — Lume-based TeamPlay

## Upstream pins

| Component | Repository | Commit |
|---|---|---|
| Lume | https://github.com/bilipp/Lume | see `LUME_UPSTREAM_COMMIT.txt` |
| LumeEngine | https://github.com/bilipp/LumeEngine | see `LUMEENGINE_UPSTREAM_COMMIT.txt` |

Vendored into this repository:

- App + Xcode project at repo root (`Lume/`, `Lume.xcodeproj`, …)
- Engine as local SPM package `./LumeEngine` (project path updated from upstream `../LumeEngine`)

## Why Xcode 26.4+ / tvOS 18 (not 16 / 17)

Upstream Lume documents:

- **Xcode 26.4** or later
- **tvOS 18.0** deployment target (also iOS 18+, macOS 15+)
- Built with the **iOS 26 SDK**; Liquid Glass / iOS 26 navigation where available
- Automated tests target **iOS 26.4+ Simulator** (not tvOS)

Early TeamPlay drafts that declared tvOS 17 / Xcode 16 are **invalid** for this Lume-based tree. Cursor must not reintroduce those lower targets without an explicit, tested fork of Lume’s platform requirements.

## Build verification checklist (Mac)

1. Install Xcode 26.4+ and a tvOS 18 simulator runtime.
2. `open Lume.xcodeproj` → scheme `Lume` → Apple TV 4K (tvOS 18).
3. Optional: first build original upstream Lume (sibling `LumeEngine`) for comparison, then this TeamPlay tree.
4. Confirm launch screen / home and **Settings → About** shows **TeamPlay**.
5. Add a user M3U URL → browse groups → play a channel → zap with the Siri Remote → return to catalog.
6. Capture Simulator screenshots for the PR.

## Cloud agent note

Linux Cloud agents cannot run Xcode or the tvOS Simulator. Mac verification requires a Mac with Xcode 26.4+ (or a Cursor private worker that has this repository + Xcode). Record actual build logs and screenshots in `docs/BUILD_RESULTS.md` when available.
