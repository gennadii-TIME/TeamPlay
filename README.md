# TeamPlay

IPTV player for **Apple TV** with **user-provided** playlists.

Canonical plan: [`docs/PRODUCT_PLAN.md`](docs/PRODUCT_PLAN.md) ([issue #3](https://github.com/gennadii-TIME/TeamPlay/issues/3)).

**#1 (this branch):** working tvOS prototype on a Lume-inspired stack (AGPL-3.0) — add/manage M3U, browse live TV, play with AVPlayer. No bundled channels or credentials.

## Requirements

- macOS with Xcode 16+
- tvOS 17.0+ Simulator or Apple TV

## Run

```bash
open TeamPlay.xcodeproj
```

Select scheme **TeamPlay** → Apple TV simulator → `⌘R`. Paste your M3U/M3U8 URL on first launch.

## #1 scope

- Add / rename / refresh / delete M3U sources
- Groups, search, logos, favorites, recent, list resume after player
- Full-screen AVPlayer, retry on stream errors, Up/Down channel zap
- SwiftData local catalog; archive capability stored from M3U hints (`showsArchive`) — **no archive UI yet**

## Next PRs (not in #1)

1. 30-language localization  
2. EPG + archive detection  
3. Archive playback + seeking  
4. #2 monetization  

Do not merge to `main` without review.

## Cloud verification

Linux Cloud has no Xcode/tvOS Simulator. Parser smoke test:

```bash
python3 Scripts/verify_m3u_parser.py
```

## License

AGPL-3.0. M3U parser adapted from [Lume](https://github.com/bilipp/Lume) — see [`NOTICE`](NOTICE).
