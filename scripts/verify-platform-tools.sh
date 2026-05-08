#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

tmp="$(mktemp)"
trap 'rm -f "$tmp"' EXIT

if [ "${SILT_SKIP_CABAL_TEST:-0}" != "1" ]; then
  cabal test all
fi
cabal build exe:silt
cabal exec -- silt fmt test/fixtures/format/messy.silt > "$tmp"
diff -u test/fixtures/format/clean.silt "$tmp"
cabal exec -- silt fmt --check test/fixtures/format/clean.silt

if cabal exec -- silt fmt --check test/fixtures/format/messy.silt >/dev/null 2>&1; then
  echo "expected messy formatter fixture to fail --check" >&2
  exit 1
fi

git diff --check
