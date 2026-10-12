#!/bin/bash
# Actual backend HTTP export -> test-target-only resources -> real client owner.
set -euo pipefail
cd "$(dirname "$0")/../.."
if [[ $# != 2 || "$1" != --backend-path ]]; then
  echo 'Usage: validate-session-contract.sh --backend-path <checkout>' >&2
  exit 2
fi
backend_path="$(cd "$2" && pwd)"
bash scripts/ios/prepare-session-contract.sh --backend-path "$backend_path"
results_dir="$(pwd)/TestResults/session-contract-consumer-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$results_dir"
cleanup() {
  rm -rf PumpSyncTests/SessionContractArtifacts
  xcodegen generate > "$results_dir/project-cleanup.log" 2>&1
}
trap cleanup EXIT
PUMPSYNC_TEST_LOG="$results_dir/frontend.log" bash scripts/ios/validate-tests.sh \
  -jobs 1 -parallel-testing-enabled NO -derivedDataPath "$results_dir/DerivedData" -only-testing:PumpSyncTests/SessionContractConsumerTests \
  -resultBundlePath "$results_dir/frontend.xcresult"
# A missing-resource skip cannot satisfy this lane.
if grep -E 'SessionContractConsumerTests.*skipped|Executed 0 tests' "$results_dir/frontend.log"; then exit 1; fi
if ! grep -E "Executed 2 tests, with 0 failures" "$results_dir/frontend.log"; then exit 1; fi
echo "Pinned session contract passed. Evidence: $results_dir"
