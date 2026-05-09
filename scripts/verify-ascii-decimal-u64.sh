#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

if [ "${SILT_SKIP_CABAL_TEST:-0}" != "1" ]; then
  cabal test all
fi
cabal build exe:silt
silt_bin="$(cabal list-bin exe:silt)"

ascii_decimal_sources=(
  stdlib/core.silt
  stdlib/nat.silt
  stdlib/bytes.silt
  stdlib/text.silt
  stdlib/ascii.silt
  stdlib/ascii-decimal.silt
  stdlib/hosted.silt
  examples/ascii-decimal-u64.silt
)

"$silt_bin" check "${ascii_decimal_sources[@]}" >/dev/null

ascii_decimal_c="$("$silt_bin" emit-c-bundle "${ascii_decimal_sources[@]}" -- ascii-decimal-u64-test)"
if ! grep -Fq 'for (uint64_t index_' <<<"$ascii_decimal_c"; then
  echo "ascii decimal parser did not lower through a length-driven loop" >&2
  exit 1
fi
if ! grep -Fq '(*((uint8_t*)' <<<"$ascii_decimal_c"; then
  echo "ascii decimal parser did not load bytes through explicit byte pointers" >&2
  exit 1
fi
if ! grep -Fq '1844674407370955161ULL' <<<"$ascii_decimal_c"; then
  echo "ascii decimal parser did not retain the U64 overflow boundary" >&2
  exit 1
fi
if ! grep -Fq '<= 9ULL' <<<"$ascii_decimal_c"; then
  echo "ascii decimal parser did not retain decimal digit-value guard evidence" >&2
  exit 1
fi
if ! grep -Fq '<= 5ULL' <<<"$ascii_decimal_c"; then
  echo "ascii decimal parser did not retain the final U64 digit bound" >&2
  exit 1
fi
if ! grep -Fq '* 10ULL) + (((uint64_t)byte_' <<<"$ascii_decimal_c"; then
  echo "ascii decimal parser did not retain base-10 accumulation evidence" >&2
  exit 1
fi
if ! grep -Fq 'silt_static_ascii_decimal_max_bytes' <<<"$ascii_decimal_c"; then
  echo "ascii decimal parser did not retain static byte-backed max-value evidence" >&2
  exit 1
fi

test_output="$("$silt_bin" test ascii-decimal-u64-test)"
if ! grep -Fq 'PASS [ascii-decimal-u64-test]' <<<"$test_output"; then
  echo "silt test did not run ascii-decimal-u64-test successfully" >&2
  echo "$test_output" >&2
  exit 1
fi

git diff --check
