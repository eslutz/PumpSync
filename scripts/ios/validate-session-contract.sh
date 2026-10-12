#!/bin/bash
# Actual backend HTTP export -> test-target-only resources -> real client owner.
set -euo pipefail
cd "$(dirname "$0")/../.."
if [[ $# != 2 || "$1" != --backend-path ]]; then
  echo 'Usage: validate-session-contract.sh --backend-path <checkout>' >&2
  exit 2
fi
backend_path="$(cd "$2" && pwd)"
manifest=PumpSyncTests/session-contract-manifest.json
revision="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["revision"])' "$manifest")"
if [[ "$(git -C "$backend_path" rev-parse HEAD)" != "$revision" ]]; then
  echo 'Backend HEAD does not match the test-only manifest revision.' >&2
  exit 1
fi
if [[ -n "$(git -C "$backend_path" status --porcelain)" ]]; then
  echo 'The pinned backend checkout must be clean.' >&2
  exit 1
fi
results_dir="$(pwd)/TestResults/session-contract-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$results_dir"
resource_dir=PumpSyncTests/SessionContractArtifacts
if [[ -e "$resource_dir" ]]; then
  echo 'Contract resource directory already exists; preserve/remove the prior run explicitly.' >&2
  exit 1
fi
artifact_dir="$(mktemp -d /tmp/pumpsync-session-contract.XXXXXX)"
cleanup() {
  rm -rf "$resource_dir" "$artifact_dir"
  xcodegen generate > "$results_dir/project-cleanup.log" 2>&1
}
trap cleanup EXIT
printf '%s\n' "$revision" > "$results_dir/backend-revision.txt"
set +e
(cd "$backend_path" && PUMPSYNC_SESSION_CONTRACT_EXPORT="$artifact_dir" \
  dotnet test PumpSync.Backend.slnx --configuration Release --disable-build-servers -m:1 /nr:false \
  --filter FullyQualifiedName~SessionContractTests) 2>&1 | tee "$results_dir/backend.log"
pipeline_status=("${PIPESTATUS[@]}")
set -e
if (( pipeline_status[0] != 0 || pipeline_status[1] != 0 )); then exit 1; fi
if grep -Ei '(^|[[:space:]])warning([[:space:]:]|[[:space:]]+[A-Z]+[0-9]+:)' "$results_dir/backend.log"; then exit 1; fi
for mode in hosted selfHosted; do
  test -s "$artifact_dir/$mode.json"
done
mkdir "$resource_dir"
cp "$artifact_dir/hosted.json" "$artifact_dir/selfHosted.json" "$resource_dir/"
cp "$artifact_dir/hosted.json" "$artifact_dir/selfHosted.json" "$results_dir/"
PUMPSYNC_TEST_LOG="$results_dir/frontend.log" bash scripts/ios/validate-tests.sh \
  -jobs 1 -parallel-testing-enabled NO -derivedDataPath "$results_dir/DerivedData" -only-testing:PumpSyncTests/SessionContractConsumerTests \
  -resultBundlePath "$results_dir/frontend.xcresult"
# A missing-resource skip cannot satisfy this lane.
if grep -E 'SessionContractConsumerTests.*skipped|Executed 0 tests' "$results_dir/frontend.log"; then exit 1; fi
if ! grep -E "Executed 2 tests, with 0 failures" "$results_dir/frontend.log"; then exit 1; fi
echo "Pinned session contract passed. Evidence: $results_dir"
