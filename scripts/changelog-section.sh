#!/bin/bash
# Print the CHANGELOG.md body for one version, without its heading.
#
# Usage:
#   scripts/changelog-section.sh 0.3.0
#
# Exits non-zero when the version has no section, which is how the release
# workflow catches a tag pushed before the changelog was updated.

set -euo pipefail

cd "$(dirname "$0")/.."

VERSION="${1:?usage: changelog-section.sh <version>}"
VERSION="${VERSION#v}"

section="$(awk -v version="$VERSION" '
    $0 ~ "^## \\[" version "\\]" { inside = 1; next }
    inside && /^## / { exit }
    inside { print }
' CHANGELOG.md)"

# Trim the blank lines the heading boundaries leave behind.
section="$(printf "%s\n" "$section" | sed -e '/./,$!d' | sed -e :a -e '/^\n*$/{$d;N;};/\n$/ba')"

if [ -z "$section" ]; then
    echo "CHANGELOG.md has no entry for $VERSION" >&2
    exit 1
fi

printf "%s\n" "$section"
