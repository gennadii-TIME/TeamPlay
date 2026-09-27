#!/usr/bin/env bash
# Build TeamPlay (Lume scheme) for every first-release Apple platform.
# Requires macOS + Xcode 26.4+ and the matching simulator runtimes.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

SPM="${TEAMPLAY_SPM_DIR:-$HOME/Library/Developer/Lume-SharedSPM}"
DD="${TEAMPLAY_DERIVED_DATA:-/tmp/teamplay-dd-all}"
LOG_DIR="${TEAMPLAY_BUILD_LOG_DIR:-$ROOT/docs/build-logs}"
mkdir -p "$LOG_DIR" "$SPM"

# Optional local signing overrides (needed on Mac hosts without upstream team CHG45F8MCL).
# Example: TEAMPLAY_DEVELOPMENT_TEAM=7Q4F885549 ./Scripts/build-all-platforms.sh
EXTRA_BUILD_FLAGS=()
if [[ -n "${TEAMPLAY_DEVELOPMENT_TEAM:-}" ]]; then
  EXTRA_BUILD_FLAGS+=(
    -allowProvisioningUpdates
    "DEVELOPMENT_TEAM=${TEAMPLAY_DEVELOPMENT_TEAM}"
    CODE_SIGN_STYLE=Automatic
  )
fi

# CloudKit is disabled in Lume.entitlements / LumeApp.isCloudKitSyncConfigured until
# a TeamPlay iCloud container is registered. No temporary entitlements override needed.
xcodebuild -version | tee "$LOG_DIR/xcode-version.txt"

# Prefer device names present on current Xcode; override via TEAMPLAY_*_DEST.
destinations=(
  "${TEAMPLAY_TVOS_DEST:-platform=tvOS Simulator,name=Apple TV 4K (3rd generation)}"
  "${TEAMPLAY_IPHONE_DEST:-platform=iOS Simulator,name=iPhone 17 Pro}"
  "${TEAMPLAY_IPAD_DEST:-platform=iOS Simulator,name=iPad Pro 13-inch (M5)}"
  "${TEAMPLAY_MACOS_DEST:-platform=macOS}"
)

names=(tvOS iPhone iPad macOS)
failed=0

for i in "${!destinations[@]}"; do
  name="${names[$i]}"
  dest="${destinations[$i]}"
  log="$LOG_DIR/build-${name}.log"
  echo "=== Building $name ($dest) ===" | tee "$log"
  if xcodebuild build \
      -project Lume.xcodeproj \
      -scheme Lume \
      -destination "$dest" \
      -clonedSourcePackagesDirPath "$SPM" \
      -derivedDataPath "$DD" \
      "${EXTRA_BUILD_FLAGS[@]}" \
      >>"$log" 2>&1; then
    echo "OK $name" | tee -a "$log"
  else
    echo "FAIL $name (see $log)" | tee -a "$log"
    failed=$((failed + 1))
  fi
done

echo "=== Summary ==="
echo "Failed platforms: $failed"
echo "Logs: $LOG_DIR"
exit "$failed"
