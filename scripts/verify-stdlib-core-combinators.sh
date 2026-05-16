#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

if [ "${SILT_SKIP_CABAL_TEST:-0}" != "1" ]; then
  cabal test all
fi
cabal build exe:silt
silt_bin="$(cabal list-bin exe:silt)"

stdlib_sources=(
  stdlib/core.silt
  stdlib/nat.silt
  stdlib/bytes.silt
  stdlib/text.silt
  stdlib/hosted.silt
  examples/hosted-hello.silt
  examples/nat-recursion.silt
  examples/list-recursion.silt
  test/fixtures/stdlib/stdlib-tests.silt
)

expect_norm() {
  local name="$1"
  local expected="$2"
  local actual
  actual="$("$silt_bin" norm "${stdlib_sources[@]}" -- "$name")"
  if [ "$actual" != "$expected" ]; then
    echo "unexpected $name normalization: $actual" >&2
    echo "expected: $expected" >&2
    exit 1
  fi
}

"$silt_bin" check "${stdlib_sources[@]}" >/dev/null

expect_norm stdlib-option-map-sample "(u64 42)"
expect_norm stdlib-option-map-none-sample "(u64 13)"
expect_norm stdlib-option-and-then-sample "(u64 42)"
expect_norm stdlib-option-and-then-none-sample "(u64 17)"
expect_norm stdlib-option-and-then-continuation-none-sample "(u64 23)"
expect_norm stdlib-result-map-sample "(u64 7)"
expect_norm stdlib-result-map-error-preserve-sample "False"
expect_norm stdlib-result-map-err-sample "(u64 99)"
expect_norm stdlib-result-map-err-ok-sample "(u64 7)"
expect_norm stdlib-result-and-then-sample "(u64 7)"
expect_norm stdlib-result-and-then-error-sample "False"
expect_norm stdlib-result-and-then-continuation-error-sample "False"
expect_norm stdlib-result-error-ok-sample "(u64 77)"
expect_norm stdlib-list-tail-sample "(u64 2)"
expect_norm stdlib-list-tail-nil-sample "(u64 55)"
expect_norm stdlib-list-head-option-sample "(u64 9)"
expect_norm stdlib-list-head-option-nil-sample "(u64 77)"
expect_norm stdlib-list-tail-option-sample "(u64 2)"
expect_norm stdlib-list-tail-option-nil-sample "(u64 55)"
expect_norm stdlib-list-elim-sum-sample "(u64 6)"
expect_norm stdlib-list-length-sample "(u64 2)"
expect_norm stdlib-list-length-nil-sample "(u64 0)"
expect_norm stdlib-list-map-sample "(u64 10)"
expect_norm stdlib-list-fold-right-sample "(u64 9)"
expect_norm stdlib-list-append-length-sample "(u64 3)"
expect_norm stdlib-list-append-empty-left-sample "(u64 44)"
expect_norm stdlib-list-filter-length-sample "(u64 2)"
expect_norm stdlib-list-reverse-head-sample "(u64 5)"
expect_norm stdlib-list-recursion-test "True"
expect_norm stdlib-nat-add-sample "(u64 5)"
expect_norm stdlib-nat-add-zero-left-sample "(u64 2)"
expect_norm stdlib-nat-add-zero-right-sample "(u64 2)"
expect_norm stdlib-nat-mul-sample "(u64 6)"
expect_norm stdlib-nat-mul-zero-sample "(u64 0)"
expect_norm stdlib-nat-mul-zero-left-sample "(u64 0)"
expect_norm stdlib-nat-pred-zero-sample "(u64 0)"
expect_norm stdlib-nat-pred-succ-sample "(u64 2)"
expect_norm stdlib-nat-sub-sample "(u64 3)"
expect_norm stdlib-nat-sub-underflow-sample "(u64 0)"
expect_norm stdlib-nat-lte-true-sample "True"
expect_norm stdlib-nat-lte-equal-sample "True"
expect_norm stdlib-nat-lte-false-sample "False"
expect_norm stdlib-nat-eq-true-sample "True"
expect_norm stdlib-nat-eq-false-sample "False"
expect_norm stdlib-nat-lt-true-sample "True"
expect_norm stdlib-nat-lt-equal-sample "False"
expect_norm stdlib-nat-lt-false-sample "False"
expect_norm stdlib-nat-order-test "True"
expect_norm nat-recursion-factorial-five "(u64 120)"
expect_norm nat-recursion-fibonacci-ten "(u64 55)"
expect_norm nat-recursion-test "True"
expect_norm list-recursion-length-three "(u64 3)"
expect_norm list-recursion-length-empty "(u64 0)"
expect_norm list-recursion-fold-sum "(u64 6)"
expect_norm list-recursion-map-head "(u64 11)"
expect_norm list-recursion-append-length "(u64 5)"
expect_norm list-recursion-filter-length "(u64 2)"
expect_norm list-recursion-reverse-head "(u64 3)"
expect_norm list-recursion-test "True"
expect_norm stdlib-combinator-happy-test "True"
expect_norm stdlib-combinator-fallback-test "True"
expect_norm stdlib-combinator-test "True"

test_output="$("$silt_bin" test stdlib-test)"
if ! grep -Fq 'PASS [stdlib-test]' <<<"$test_output"; then
  echo "silt test did not run stdlib-test successfully" >&2
  echo "$test_output" >&2
  exit 1
fi

nat_test_output="$("$silt_bin" test nat-recursion-test)"
if ! grep -Fq 'PASS [nat-recursion-test]' <<<"$nat_test_output"; then
  echo "silt test did not run nat-recursion-test successfully" >&2
  echo "$nat_test_output" >&2
  exit 1
fi

list_test_output="$("$silt_bin" test list-recursion-test)"
if ! grep -Fq 'PASS [list-recursion-test]' <<<"$list_test_output"; then
  echo "silt test did not run list-recursion-test successfully" >&2
  echo "$list_test_output" >&2
  exit 1
fi

git diff --check
