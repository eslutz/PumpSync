#!/bin/bash
# Exhaustive actual simulator text settings; no launch-environment approximation.
set -euo pipefail
cd "$(dirname "$0")/../.."
if (( $# != 1 )); then
  echo "Usage: bash Scripts/ios/validate-design-accessibility.sh <isolated-simulator-id>" >&2
  exit 2
fi
device_id="$1"
results_dir="${PUMPSYNC_DESIGN_RESULTS_DIR:-TestResults/design-type-$(date -u +%Y%m%dT%H%M%SZ)}"
mkdir -p "$results_dir"
results_dir="$(cd "$results_dir" && pwd)"
derived_data_path="${PUMPSYNC_DESIGN_DERIVED_DATA:-$results_dir/DerivedData}"
original_size="$(xcrun simctl ui "$device_id" content_size)"
trap 'xcrun simctl ui "$device_id" content_size "$original_size" >/dev/null 2>&1 || true' EXIT
xcodebuild -version > "$results_dir/environment.txt"
xcrun simctl list devices available --json > "$results_dir/devices.json"
git ls-files -z --cached --others --exclude-standard -- PumpSync PumpSyncTests PumpSyncUITests project.yml PumpSync.xcodeproj \
  | xargs -0 shasum -a 256 > "$results_dir/source-hashes.txt"
export PUMPSYNC_TEST_DESTINATION="platform=iOS Simulator,id=$device_id"
for size in extra-small small medium large extra-large extra-extra-large extra-extra-extra-large \
  accessibility-medium accessibility-large accessibility-extra-large accessibility-extra-extra-large accessibility-extra-extra-extra-large; do
  echo "Checking actual simulator content size: $size"
  xcrun simctl ui "$device_id" content_size "$size"
  xcrun simctl ui "$device_id" content_size > "$results_dir/$size-setting.txt"
  PUMPSYNC_TEST_LOG="$results_dir/$size.log" bash Scripts/ios/validate-tests.sh \
    -jobs 1 -parallel-testing-enabled NO -derivedDataPath "$derived_data_path" \
    -only-testing:PumpSyncUITests/PumpSyncUITests/testDesignReviewAdaptiveReachability \
    -resultBundlePath "$results_dir/$size.xcresult" > "$results_dir/$size-console.log" 2>&1
  xcrun xcresulttool get test-results summary --path "$results_dir/$size.xcresult" > "$results_dir/$size-summary.json"
done
shasum -a 256 -c "$results_dir/source-hashes.txt" > "$results_dir/source-verification.txt"
echo "All twelve text categories passed. Evidence: $results_dir"
