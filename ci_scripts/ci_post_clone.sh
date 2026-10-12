#!/bin/sh

set -eu

cd "${CI_PRIMARY_REPOSITORY_PATH:-$(cd "$(dirname "$0")/.." && pwd)}"

if ! command -v xcodegen >/dev/null 2>&1; then
  brew install xcodegen
fi

bash scripts/ios/prepare-session-contract.sh
xcodegen generate
