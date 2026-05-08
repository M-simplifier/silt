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
  test_output="$("$silt_bin" test hello-test)"
  if ! grep -Fq 'PASS [hello-test]' <<<"$test_output"; then
    echo "selected package test did not report hello-test success" >&2
    echo "$test_output" >&2
    exit 1
  fi
  if ! grep -Fq 'silt package tests: 1 passed' <<<"$test_output"; then
    echo "selected package test did not report one passing test" >&2
    echo "$test_output" >&2
    exit 1
  fi
  if "$silt_bin" test hello; then
    echo "expected bin target selection through silt test to fail" >&2
    exit 1
  fi
  if "$silt_bin" test missing-test; then
    echo "expected unknown test target selection to fail" >&2
    exit 1
  fi
  if "$silt_bin" test hello-test extra; then
    echo "expected unsupported extra silt test args to fail" >&2
    exit 1
  fi
)

(
  cd test/fixtures/packages/failing
  if "$silt_bin" test; then
    echo "expected failing package test to fail" >&2
    exit 1
  fi
  if "$silt_bin" test failing-test; then
    echo "expected selected failing package test to fail" >&2
    exit 1
  fi
)

git diff --check
