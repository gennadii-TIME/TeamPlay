# TeamPlay architecture

Implements TeamPlay #1 against [`PRODUCT_PLAN.md`](PRODUCT_PLAN.md). Stack inspired by [Lume](https://github.com/bilipp/Lume) (AGPL), branded and scoped for Apple TV + user M3U.

## Layers

```
TeamPlayApp
 └─ RootView
     ├─ OnboardingView            # user M3U URL only (no bundled content)
     └─ LiveTVHomeView            # groups, search, favorites, recent
         ├─ PlaylistManagerView   # rename / refresh / delete
         └─ PlayerView            # AVPlayer + zap + retry

Services/
  Network/   M3UParser, M3UClient
  Sync/      PlaylistImporter
  Player/    PlaybackController

Models/      Playlist, LiveChannel   (SwiftData, local only)
```

## PRODUCT_PLAN mapping

| Plan section | #1 status |
|---|---|
| §1 Playlists & live TV | Implemented (M3U; Xtream deferred) |
| §2 EPG & archive | Storage seams only (`epgURL`, `epgChannelId`, `showsArchive`) — separate PRs |
| §3 Languages | English UI for prototype — 30-language PR next |
| §4 Design / a11y | Focus-first tvOS layout; iterate with UI review |
| §5 Monetization | Out of scope (#2) |

## Archive rule (enforced early)

Import records catch-up only when the playlist advertises it (`catchup` / `catchup-days` / `timeshift` / `tvg-rec`). Future Archive UI **must** gate on `LiveChannel.showsArchive` and must not invent archive for plain live HLS.

## Anti-goals

- No merge to `main` without human verification
- No bundled playlists, credentials, or channels
- No EPG/archive/seek/localization UI in this PR
