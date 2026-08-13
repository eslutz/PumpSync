#!/bin/sh

set -eu

repository_root="$(cd "$(dirname "$0")/../.." && pwd)"
validator="$repository_root/scripts/validate-version.sh"
fixture="$(mktemp)"
trap 'rm -f "$fixture"' EXIT

write_version() {
  version="$1"
  printf 'settings:\n  base:\n    MARKETING_VERSION: "%s"\n' "$version" > "$fixture"
}

expect_success() {
  description="$1"
  ref="$2"
  if ! "$validator" --project "$fixture" --ref "$ref" >/dev/null 2>&1; then
    echo "Expected success: $description" >&2
    exit 1
  fi
}

expect_failure() {
  description="$1"
  ref="$2"
  if "$validator" --project "$fixture" --ref "$ref" >/dev/null 2>&1; then
    echo "Expected failure: $description" >&2
    exit 1
  fi
}

write_version "1.0.0"
expect_success "three-component version on a branch" "refs/heads/main"
expect_success "matching stable release tag" "refs/tags/v1.0.0"

write_version "1.0"
expect_failure "two-component marketing version" "refs/heads/main"

write_version "1.0.0"
expect_failure "release tag that differs from MARKETING_VERSION" "refs/tags/v1.0.1"

write_version "01.0.0"
expect_failure "leading zero in a SemVer component" "refs/heads/main"

echo "Frontend version validation tests passed."
