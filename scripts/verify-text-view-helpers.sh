#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

if [ "${SILT_SKIP_CABAL_TEST:-0}" != "1" ]; then
  cabal test all
fi
cabal build exe:silt
silt_bin="$(cabal list-bin exe:silt)"

text_view_sources=(
  stdlib/core.silt
  stdlib/nat.silt
  stdlib/bytes.silt
  stdlib/text.silt
  examples/text-views.silt
)

expect_norm() {
  local name="$1"
  local expected="$2"
  local actual
  actual="$("$silt_bin" norm "${text_view_sources[@]}" -- "$name")"
  if [ "$actual" != "$expected" ]; then
    echo "unexpected $name normalization: $actual" >&2
    echo "expected: $expected" >&2
    exit 1
  fi
}

"$silt_bin" check "${text_view_sources[@]}" >/dev/null

expect_norm text-view-sample-len "(u64 9)"
expect_norm byte-view-is-empty "True"
expect_norm text-view-is-empty "True"
expect_norm byte-view-take-len "(u64 4)"
expect_norm byte-view-take-too-far-len "(u64 9)"
expect_norm byte-view-drop-len "(u64 5)"
expect_norm byte-view-drop-base "(addr 4100)"
expect_norm byte-view-drop-too-far-len "(u64 0)"
expect_norm byte-view-drop-too-far-base "(addr 4105)"
expect_norm text-view-take-len "(u64 4)"
expect_norm text-view-take-too-far-len "(u64 9)"
expect_norm text-view-drop-len "(u64 5)"
expect_norm text-view-drop-base "(addr 4100)"
expect_norm text-view-drop-too-far-len "(u64 0)"
expect_norm text-view-drop-too-far-base "(addr 4105)"

git diff --check
