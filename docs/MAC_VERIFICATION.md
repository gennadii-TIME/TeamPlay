# Mac verification cheat-sheet (PR #6)

Run this in **Cursor on your Mac** (not Linux Cloud).

1. Open the TeamPlay repo → branch `cursor/teamplay-lume-base-8341` → pull / merge `origin/main`.
2. Confirm toolchain:
   - `xcodebuild -version` → need **26.4+**
   - `xcodebuild -showsdks` and `xcrun simctl list devices available`
3. `./Scripts/build-all-platforms.sh`
4. Fix any build errors; re-run until all five destinations succeed.
5. Manual: add your M3U, play a channel on tvOS / iPhone / iPad / Mac / Vision Pro; on Apple TV also zap and return to catalog.
6. Fill `docs/BUILD_RESULTS.md`, commit, push, attach screenshots to draft **PR #6**.
7. Leave PR #6 as draft until the matrix is complete. Do not merge PR #4.

If Xcode is older than 26.4, write the exact version and missing SDK/simulator in `BUILD_RESULTS.md` instead of forcing a lower deployment target.
