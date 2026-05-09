#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

if [ "${SILT_SKIP_CABAL_TEST:-0}" != "1" ]; then
  cabal test all
fi
cabal build exe:silt
silt_bin="$(cabal list-bin exe:silt)"

ascii_sources=(
  stdlib/core.silt
  stdlib/ascii.silt
  examples/ascii-predicates.silt
)

expect_norm() {
  local name="$1"
  local expected="$2"
  local actual
  actual="$("$silt_bin" norm "${ascii_sources[@]}" -- "$name")"
  if [ "$actual" != "$expected" ]; then
    echo "unexpected $name normalization: $actual" >&2
    echo "expected: $expected" >&2
    exit 1
  fi
}

"$silt_bin" check "${ascii_sources[@]}" >/dev/null

expect_norm ascii-digit-zero-sample "True"
expect_norm ascii-digit-nine-sample "True"
expect_norm ascii-digit-slash-sample "False"
expect_norm ascii-digit-colon-sample "False"
expect_norm ascii-lower-a-sample "True"
expect_norm ascii-lower-z-sample "True"
expect_norm ascii-lower-backtick-sample "False"
expect_norm ascii-lower-upper-sample "False"
expect_norm ascii-lower-left-brace-sample "False"
expect_norm ascii-upper-a-sample "True"
expect_norm ascii-upper-z-sample "True"
expect_norm ascii-upper-at-sample "False"
expect_norm ascii-upper-left-bracket-sample "False"
expect_norm ascii-alpha-lower-sample "True"
expect_norm ascii-alpha-upper-sample "True"
expect_norm ascii-alpha-symbol-sample "False"
expect_norm ascii-alnum-digit-sample "True"
expect_norm ascii-alnum-upper-sample "True"
expect_norm ascii-alnum-symbol-sample "False"
expect_norm ascii-hex-digit-sample "True"
expect_norm ascii-hex-upper-a-sample "True"
expect_norm ascii-hex-upper-sample "True"
expect_norm ascii-hex-g-sample "False"
expect_norm ascii-hex-lower-a-sample "True"
expect_norm ascii-hex-lower-f-sample "True"
expect_norm ascii-hex-lower-g-sample "False"
expect_norm ascii-space-sample "True"
expect_norm ascii-space-tab-sample "False"
expect_norm ascii-whitespace-tab-sample "True"
expect_norm ascii-whitespace-line-feed-sample "True"
expect_norm ascii-whitespace-vertical-tab-sample "True"
expect_norm ascii-whitespace-form-feed-sample "True"
expect_norm ascii-whitespace-carriage-return-sample "True"
expect_norm ascii-whitespace-space-sample "True"
expect_norm ascii-whitespace-letter-sample "False"
expect_norm ascii-digit-boundary-test "True"
expect_norm ascii-alpha-boundary-test "True"
expect_norm ascii-alnum-boundary-test "True"
expect_norm ascii-hex-boundary-test "True"
expect_norm ascii-space-boundary-test "True"
expect_norm ascii-whitespace-boundary-test "True"
expect_norm ascii-predicate-test "True"

test_output="$("$silt_bin" test ascii-test)"
if ! grep -Fq 'PASS [ascii-test]' <<<"$test_output"; then
  echo "silt test did not run ascii-test successfully" >&2
  echo "$test_output" >&2
  exit 1
fi

git diff --check
