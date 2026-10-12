#!/bin/bash
# Generate test-only responses from the pinned actual backend.
set -euo pipefail
cd "$(dirname "$0")/../.."
manifest=PumpSyncTests/session-contract-manifest.json
revision="$(python3 -c 'import json; print(json.load(open("PumpSyncTests/session-contract-manifest.json"))["revision"])')"
if [[ $# == 2 && "$1" == --backend-path ]]; then
  backend_path="$(cd "$2" && pwd)"
elif [[ $# == 0 ]]; then
  backend_path="$(pwd)/.session-contract-backend"
  if [[ ! -d "$backend_path/.git" ]]; then
    repository="$(python3 -c 'import json; print(json.load(open("PumpSyncTests/session-contract-manifest.json"))["repository"])')"
    git clone "https://github.com/$repository.git" "$backend_path"
    git -C "$backend_path" checkout --detach "$revision"
  fi
else
  echo 'Usage: prepare-session-contract.sh [--backend-path <clean pinned checkout>]' >&2
  exit 2
fi
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
  rm -rf "$artifact_dir"
}
trap cleanup EXIT
printf '%s\n' "$revision" > "$results_dir/backend-revision.txt"
if ! (cd "$backend_path" && dotnet --version >/dev/null 2>&1); then
  sdk_version="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["sdk"]["version"])' "$backend_path/global.json")"
  curl --fail --location https://dot.net/v1/dotnet-install.sh --output "$artifact_dir/dotnet-install.sh"
  bash "$artifact_dir/dotnet-install.sh" --version "$sdk_version" --install-dir "$artifact_dir/dotnet"
  export PATH="$artifact_dir/dotnet:$PATH"
fi
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
echo "Prepared pinned backend contract resources. Evidence: $results_dir"
