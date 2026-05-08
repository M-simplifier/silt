#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

if [ "${SILT_SKIP_CABAL_TEST:-0}" != "1" ]; then
  cabal test all
fi
cabal build exe:silt
silt_bin="$(cabal list-bin exe:silt)"

rm -rf test/fixtures/packages/hello/out test/fixtures/packages/failing/out

(
  cd test/fixtures/packages/hello
  "$silt_bin" build
  test -x out/silt/debug/hello
  "$silt_bin" build hello
  "$silt_bin" run
  "$silt_bin" test
)

(
  cd test/fixtures/packages/failing
  if "$silt_bin" test; then
    echo "expected failing package test to fail" >&2
    exit 1
  fi
)

git diff --check
