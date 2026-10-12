#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BIN="$(mktemp /tmp/rival-motion-probe.XXXXXX)"
trap 'rm -f "$BIN"' EXIT
cd "$ROOT"
xcrun swiftc -O -swift-version 6 -parse-as-library \
  PixelBoxingIOS/CombatCore.swift \
  PixelBoxingIOS/Weaving.swift \
  PixelBoxingIOS/WeaveMotion.swift \
  PixelBoxingIOS/CombatPresentation.swift \
  PixelBoxingIOS/CombatText.swift \
  PixelBoxingIOS/Localization.swift \
  PixelBoxingIOS/RivalAI.swift \
  PixelBoxingIOS/DefensiveMotion.swift \
  PixelBoxingIOS/FighterPose.swift \
  PixelBoxingIOS/BoxingMotion.swift \
  PixelBoxingIOSTests/MotionRegressionChecks.swift \
  scripts/MotionProbe.swift -o "$BIN"
"$BIN"