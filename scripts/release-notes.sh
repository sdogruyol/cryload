#!/usr/bin/env sh
# Extract release notes for a version from CHANGELOG.md
# Usage: scripts/release-notes.sh v4.0.0

set -eu

tag="${1:-}"
if [ -z "$tag" ]; then
  echo "Usage: scripts/release-notes.sh <tag>" >&2
  exit 1
fi

version="${tag#v}"
changelog="CHANGELOG.md"

if [ ! -f "$changelog" ]; then
  echo "Missing $changelog" >&2
  exit 1
fi

awk -v version="$version" '
  $0 ~ "^# " version " " { capture = 1; next }
  capture && /^# [0-9]/ { exit }
  capture { print }
' "$changelog"
