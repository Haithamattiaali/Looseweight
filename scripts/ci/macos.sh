#!/usr/bin/env bash
# macOS job: core engine on Apple's toolchain, then the iPhone app on the iOS Simulator:
# build, unit tests, UI tests with screenshots and a screen recording. Proof goes to ci-output/.
set -euo pipefail
cd "$(dirname "$0")/../.."
ROOT=$(pwd)
OUT="$ROOT/ci-output"
mkdir -p "$OUT"

XCODE=$(ls -d /Applications/Xcode_*.app 2>/dev/null | grep -vi beta | sort -V | tail -1 || true)
if [ -n "$XCODE" ]; then sudo xcode-select -s "$XCODE"; fi
{ xcodebuild -version; sw_vers; } | tee "$OUT/toolchain.txt"

echo "::group::Core engine tests (macOS)"
(cd Packages/LooseweightKit && swift test 2>&1 | tee "$OUT/kit-tests.log")
echo "::endgroup::"

if [ "${RUN_EVAL:-false}" = "true" ] && [ -n "${ANTHROPIC_API_KEY:-}" ]; then
  echo "::group::AI accuracy check (Nutrition5k)"
  (cd Packages/LooseweightKit && swift run -c release lw-eval --dishes "${EVAL_DISHES:-20}" --output "$OUT/eval") || echo "eval failed"
  echo "::endgroup::"
fi

if [ ! -f project.yml ]; then
  echo "No iPhone app project yet."
  exit 0
fi

command -v xcodegen >/dev/null || brew install xcodegen
xcodegen generate

DEVICE_ID=$(python3 scripts/ci/pick_simulator.py)
xcrun simctl boot "$DEVICE_ID" 2>/dev/null || true
xcrun simctl bootstatus "$DEVICE_ID" -b
xcrun simctl status_bar "$DEVICE_ID" override --time "9:41" --batteryState charged --batteryLevel 100 --cellularBars 4 --wifiBars 3 || true

echo "::group::Build"
xcodebuild -project Looseweight.xcodeproj -scheme Looseweight -destination "id=$DEVICE_ID" \
  -derivedDataPath "$ROOT/build/DerivedData" CODE_SIGNING_ALLOWED=NO -quiet build-for-testing 2>&1 | tee "$OUT/build.log"
echo "::endgroup::"

mkdir -p "$OUT/screenshots"
xcrun simctl io "$DEVICE_ID" recordVideo --codec h264 --force "$OUT/app-walkthrough.mp4" &
RECORDER=$!
sleep 2

set +e
TEST_RUNNER_SCREENSHOTS_DIR="$OUT/screenshots" xcodebuild -project Looseweight.xcodeproj -scheme Looseweight \
  -destination "id=$DEVICE_ID" -derivedDataPath "$ROOT/build/DerivedData" CODE_SIGNING_ALLOWED=NO \
  -resultBundlePath "$ROOT/build/Tests.xcresult" test-without-building > "$OUT/test.log" 2>&1
STATUS=$?
set -e
grep -E "Test (Case|Suite)|error:|failed|passed" "$OUT/test.log" | tail -300 || true

kill -INT "$RECORDER" 2>/dev/null || true
wait "$RECORDER" 2>/dev/null || true

xcrun xcresulttool export attachments --path "$ROOT/build/Tests.xcresult" --output-path "$OUT/attachments" >/dev/null 2>&1 || true
ls -la "$OUT/screenshots" || true
exit "$STATUS"
