#!/bin/bash
set -euo pipefail

# Actual app sources + Foundation/XCTest, including production localization; no stubs or fallback.
# No UI/controller substitutes, xcodegen or iOS build.
if [[ $# -gt 0 ]]; then
  echo "Usage: $0" >&2
  exit 2
fi
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BIN="$(mktemp /tmp/rival-weaving-probe.XXXXXX)"
trap 'rm -f "$BIN"' EXIT
cd "$ROOT"
FRAMEWORKS="$(xcrun --sdk macosx --show-sdk-platform-path)/Developer/Library/Frameworks"
SWIFT_SUPPORT="$(xcrun --sdk macosx --show-sdk-platform-path)/Developer/usr/lib"
xcrun --sdk macosx swiftc -O -swift-version 6 -parse-as-library -D WEAVING_PROBE \
  -F "$FRAMEWORKS" -framework XCTest -Xlinker -rpath -Xlinker "$FRAMEWORKS" \
  -I "$SWIFT_SUPPORT" -L "$SWIFT_SUPPORT" -lXCTestSwiftSupport \
  -Xlinker -rpath -Xlinker "$SWIFT_SUPPORT" \
  PixelBoxingIOS/CombatCore.swift \
  PixelBoxingIOS/Weaving.swift \
  PixelBoxingIOS/CombatPresentation.swift \
  PixelBoxingIOS/CombatText.swift \
  PixelBoxingIOS/Localization.swift \
  PixelBoxingIOS/RivalAI.swift \
  PixelBoxingIOSTests/WeavingTests.swift \
  scripts/WeavingProbe.swift -o "$BIN"
"$BIN"