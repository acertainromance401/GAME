#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BIN="$(mktemp /tmp/rival-ai-probe.XXXXXX)"
trap 'rm -f "$BIN"' EXIT
cd "$ROOT"
xcrun swiftc -O -swift-version 6 -parse-as-library \
  PixelBoxingIOS/CombatCore.swift \
  PixelBoxingIOS/Weaving.swift \
  PixelBoxingIOS/CombatPresentation.swift \
  PixelBoxingIOS/CombatText.swift \
  PixelBoxingIOS/Localization.swift \
  PixelBoxingIOS/RivalAI.swift \
  PixelBoxingIOS/CombatInput.swift \
  PixelBoxingIOS/DefensiveMotion.swift \
  scripts/AIBehaviorProbe.swift -o "$BIN"
"$BIN"