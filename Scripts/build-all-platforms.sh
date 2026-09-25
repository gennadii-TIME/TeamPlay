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

xcodebuild -version | tee "$LOG_DIR/xcode-version.txt"

destinations=(
  "platform=tvOS Simulator,name=Apple TV 4K"
  "platform=iOS Simulator,name=iPhone 17 Pro"
  "platform=iOS Simulator,name=iPad Pro 13-inch (M4)"
  "platform=macOS"
  "platform=visionOS Simulator,name=Apple Vision Pro"
)

names=(tvOS iPhone iPad macOS visionOS)
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
      >>"$log" 2>&1; then
    echo "OK $name" | tee -a "$log"
  else
    echo "FAIL $name (see $log)" | tee -a "$log"
    # Retry with generic destination ids if named sims differ on this Mac
    failed=$((failed + 1))
  fi
done

echo "=== Summary ==="
echo "Failed platforms: $failed"
echo "Logs: $LOG_DIR"
exit "$failed"
