#!/bin/bash
# Actual backend HTTP export -> test-target-only resources -> real client owner.
set -euo pipefail
cd "$(dirname "$0")/../.."
if (( $# != 0 )); then
  echo 'Usage: validate-session-contract.sh (consumes committed snapshots)' >&2
  exit 2
fi
results_dir="$(pwd)/TestResults/session-contract-consumer-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$results_dir"
PUMPSYNC_TEST_LOG="$results_dir/frontend.log" bash Scripts/ios/validate-tests.sh \
  -jobs 1 -parallel-testing-enabled NO -derivedDataPath "$results_dir/DerivedData" -only-testing:PumpSyncTests/SessionContractConsumerTests \
  -resultBundlePath "$results_dir/frontend.xcresult"
# A missing-resource skip cannot satisfy this lane.
if grep -E 'SessionContractConsumerTests.*skipped|Executed 0 tests' "$results_dir/frontend.log"; then exit 1; fi
if ! grep -E "Executed 2 tests, with 0 failures" "$results_dir/frontend.log"; then exit 1; fi
echo "Committed session contract passed. Evidence: $results_dir"
