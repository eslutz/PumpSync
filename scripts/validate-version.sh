#!/bin/sh

set -eu

project_file="project.yml"
git_ref="${GITHUB_REF:-}"

while [ "$#" -gt 0 ]; do
  case "$1" in
    --project)
      project_file="$2"
      shift 2
      ;;
    --ref)
      git_ref="$2"
      shift 2
      ;;
    *)
      echo "Unknown argument: $1" >&2
      exit 2
      ;;
  esac
done

if [ ! -f "$project_file" ]; then
  echo "Version source not found: $project_file" >&2
  exit 1
fi

version="$(awk '
  /^[[:space:]]*MARKETING_VERSION:[[:space:]]*/ {
    value = $0
    sub(/^[^:]*:[[:space:]]*/, "", value)
    gsub(/^"|"$/, "", value)
    print value
  }
' "$project_file")"

if [ -z "$version" ]; then
  echo "MARKETING_VERSION is missing from $project_file" >&2
  exit 1
fi

if [ "$(printf '%s\n' "$version" | wc -l | tr -d ' ')" -ne 1 ]; then
  echo "MARKETING_VERSION must be declared exactly once in $project_file" >&2
  exit 1
fi

if ! printf '%s\n' "$version" | grep -Eq '^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$'; then
  echo "MARKETING_VERSION must use stable MAJOR.MINOR.PATCH SemVer; found: $version" >&2
  exit 1
fi

case "$git_ref" in
  refs/tags/v*)
    tag_version="${git_ref#refs/tags/v}"
    if [ "$tag_version" != "$version" ]; then
      echo "Release tag v$tag_version does not match MARKETING_VERSION $version" >&2
      exit 1
    fi
    ;;
esac

echo "$version"
