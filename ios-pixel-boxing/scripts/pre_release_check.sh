#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

SCHEME="RIVAL"
PROJECT_FILE="RIVAL.xcodeproj"
SKIP_DEVICE_TESTS=0
DEVICE_ID=""
LOG_FILE="/tmp/rival_pre_release_$(date +%Y%m%d_%H%M%S).log"

usage() {
  cat <<'EOF'
Usage:
  ./scripts/pre_release_check.sh [--skip-device-tests] [--device-id <UDID>]

Options:
  --skip-device-tests   Skip test-without-building on a physical iPhone.
  --device-id <UDID>    Run tests on this physical iPhone UDID.
  -h, --help            Show this help message.

Default behavior:
  1) Regenerate Xcode project with XcodeGen
  2) Generic iOS build-for-testing (no code signing)
  3) Generic iOS Release build (no code signing)
  4) Optional physical device test-without-building when --device-id is provided
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --skip-device-tests)
      SKIP_DEVICE_TESTS=1
      shift
      ;;
    --device-id)
      if [[ $# -lt 2 ]]; then
        echo "[ERROR] --device-id requires a value"
        exit 1
      fi
      DEVICE_ID="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "[ERROR] Unknown option: $1"
      usage
      exit 1
      ;;
  esac
done

if [[ -n "${DEVICE_ID}" && "${SKIP_DEVICE_TESTS}" -eq 1 ]]; then
  echo "[WARN] --skip-device-tests is set, so --device-id will be ignored."
fi

require_cmd() {
  local cmd="$1"
  if ! command -v "${cmd}" >/dev/null 2>&1; then
    echo "[ERROR] Required command not found: ${cmd}"
    exit 1
  fi
}

run_step() {
  local title="$1"
  shift
  echo ""
  echo "==> ${title}"
  "$@" 2>&1 | tee -a "${LOG_FILE}"
}

echo "RIVAL iOS pre-release preflight"
echo "Project root : ${PROJECT_ROOT}"
echo "Log file     : ${LOG_FILE}"

require_cmd xcodegen
require_cmd xcodebuild

cd "${PROJECT_ROOT}"

run_step "Regenerate project (xcodegen)" xcodegen generate

run_step "Build for testing (generic iOS, unsigned)" \
  xcodebuild \
  -project "${PROJECT_FILE}" \
  -scheme "${SCHEME}" \
  -sdk iphoneos \
  -destination 'generic/platform=iOS' \
  CODE_SIGNING_ALLOWED=NO \
  build-for-testing

run_step "Release build (generic iOS, unsigned)" \
  xcodebuild \
  -project "${PROJECT_FILE}" \
  -scheme "${SCHEME}" \
  -configuration Release \
  -sdk iphoneos \
  -destination 'generic/platform=iOS' \
  CODE_SIGNING_ALLOWED=NO \
  build

if [[ "${SKIP_DEVICE_TESTS}" -eq 0 && -n "${DEVICE_ID}" ]]; then
  run_step "UI/Unit tests on physical device ${DEVICE_ID}" \
    xcodebuild \
    -project "${PROJECT_FILE}" \
    -scheme "${SCHEME}" \
    -destination "id=${DEVICE_ID}" \
    test-without-building
else
  echo ""
  echo "==> Device tests"
  echo "Skipped (provide --device-id <UDID> to run on physical iPhone)." | tee -a "${LOG_FILE}"
fi

echo ""
echo "Pre-release preflight completed successfully."
echo "Detailed log: ${LOG_FILE}"
