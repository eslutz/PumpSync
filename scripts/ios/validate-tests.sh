#!/bin/bash
# Preflight used locally and by GitHub CI. Preserve the raw log for diagnosis.
set -euo pipefail
cd "$(dirname "$0")/../.."
log_path="${PUMPSYNC_TEST_LOG:-$(mktemp /tmp/pumpsync-test-validation.XXXXXX)}"
destination="${PUMPSYNC_TEST_DESTINATION:-platform=iOS Simulator,name=iPhone 17,OS=latest}"
xcodegen generate
set +e
xcodebuild test -project PumpSync.xcodeproj -scheme PumpSync \
  -destination "$destination" "$@" 2>&1 | tee "$log_path"
pipeline_status=("${PIPESTATUS[@]}")
set -e
echo "Build and test log: $log_path"
if grep -Ei '(^|[[:space:]])warning:' "$log_path"; then
  echo "Validation failed: build/test warnings must be resolved before delivery." >&2
  exit 1
fi
if (( pipeline_status[0] != 0 )); then
  exit "${pipeline_status[0]}"
fi
exit "${pipeline_status[1]}"
