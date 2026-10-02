#!/bin/bash
# Match the Internal Beta test action observed in Xcode Cloud Build 38.
# Update these values only after checking the workflow's actual test results.
set -euo pipefail
cd "$(dirname "$0")/../.."

if (( $# != 0 )); then
  echo "Usage: bash scripts/ios/validate-cloud-tests.sh (no test filters allowed)" >&2
  exit 2
fi

expected_xcode_build="27A266a"
runtime="com.apple.CoreSimulator.SimRuntime.iOS-27-0"
device_type="com.apple.CoreSimulator.SimDeviceType.iPhone-SE-3rd-generation"
device_name="PumpSync iOS 27 SE Validation"
results_dir="${PUMPSYNC_CLOUD_RESULTS_DIR:-TestResults/cloud-$(date -u +%Y%m%dT%H%M%SZ)}"
mkdir -p "$results_dir"
results_dir="$(cd "$results_dir" && pwd)"

xcodebuild -version | tee "$results_dir/environment.txt"
if ! grep -qx "Build version $expected_xcode_build" "$results_dir/environment.txt"; then
  echo "Cloud preflight requires Xcode build $expected_xcode_build. Select the matching Xcode before running." >&2
  exit 1
fi

xcrun simctl list runtimes available --json | python3 -c '
import json, sys
runtime = next((r for r in json.load(sys.stdin)["runtimes"] if r["identifier"] == sys.argv[1] and r.get("isAvailable")), None)
if runtime is None:
    raise SystemExit("Cloud preflight requires the iOS 27.0 runtime. Install it in Xcode Settings > Components.")
print("Runtime:", runtime["name"], "build", runtime["buildversion"])
' "$runtime" | tee -a "$results_dir/environment.txt"

device_id="$(xcrun simctl list devices available --json | python3 -c '
import json, sys
devices = json.load(sys.stdin)["devices"].get(sys.argv[1], [])
print(next((d["udid"] for d in devices if d["name"] == sys.argv[2] and d.get("deviceTypeIdentifier") == sys.argv[3]), ""))
' "$runtime" "$device_name" "$device_type")"
if [[ -z "$device_id" ]]; then
  device_id="$(xcrun simctl create "$device_name" "$device_type" "$runtime")"
fi
xcrun simctl bootstatus "$device_id" -b
original_content_size="$(xcrun simctl ui "$device_id" content_size)"
trap 'xcrun simctl ui "$device_id" content_size "$original_content_size" >/dev/null 2>&1 || true' EXIT
xcrun simctl ui "$device_id" content_size large

{
  echo "Device: iPhone SE (3rd generation), iOS 27.0, $device_id"
  echo "Commit: $(git rev-parse HEAD)"
  git status --short
} | tee -a "$results_dir/environment.txt"
git ls-files -z -- PumpSync PumpSyncTests PumpSyncUITests project.yml PumpSync.xcodeproj \
  | xargs -0 shasum -a 256 > "$results_dir/source-hashes.txt"
export PUMPSYNC_TEST_DESTINATION="platform=iOS Simulator,id=$device_id"

# One complete run; never turn failures into success with retry-until-pass.
PUMPSYNC_TEST_LOG="$results_dir/full.log" bash scripts/ios/validate-tests.sh \
  -parallel-testing-enabled NO -resultBundlePath "$results_dir/full.xcresult"
xcrun xcresulttool get test-results summary --path "$results_dir/full.xcresult" > "$results_dir/full-summary.json"

# Use actual simulator text settings, rather than a launch environment variable
# that does not reliably change SwiftUI's text size. Every iteration must pass.
for text_size in large accessibility-extra-extra-extra-large; do
  xcrun simctl ui "$device_id" content_size "$text_size"
  PUMPSYNC_TEST_LOG="$results_dir/preview-$text_size.log" bash scripts/ios/validate-tests.sh \
    -parallel-testing-enabled NO -test-iterations 5 -test-repetition-relaunch-enabled YES \
    -only-testing:PumpSyncUITests/PumpSyncUITests/testSamplePreviewIsSeparateAndClosesWithoutChangingConnection \
    -resultBundlePath "$results_dir/preview-$text_size.xcresult"
  xcrun xcresulttool get test-results summary --path "$results_dir/preview-$text_size.xcresult" > "$results_dir/preview-$text_size-summary.json"
done
shasum -a 256 -c "$results_dir/source-hashes.txt" > "$results_dir/source-verification.txt"
echo "Cloud device preflight passed. Evidence: $results_dir"
