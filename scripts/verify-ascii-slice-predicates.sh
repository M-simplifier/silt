#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

if [ "${SILT_SKIP_CABAL_TEST:-0}" != "1" ]; then
  cabal test all
fi
cabal build exe:silt
silt_bin="$(cabal list-bin exe:silt)"

ascii_slice_sources=(
  stdlib/core.silt
  stdlib/nat.silt
  stdlib/bytes.silt
  stdlib/text.silt
  stdlib/ascii.silt
  stdlib/ascii-slice.silt
  stdlib/hosted.silt
  examples/ascii-slice-predicates.silt
)

"$silt_bin" check "${ascii_slice_sources[@]}" >/dev/null

ascii_slice_c="$("$silt_bin" emit-c-bundle "${ascii_slice_sources[@]}" -- ascii-slice-predicate-test)"
if ! grep -Fq 'for (uint64_t index_' <<<"$ascii_slice_c"; then
  echo "ascii-slice predicates did not lower through a length-driven loop" >&2
  exit 1
fi
if ! grep -Fq '(*((uint8_t*)' <<<"$ascii_slice_c"; then
  echo "ascii-slice predicates did not load bytes through explicit byte pointers" >&2
  exit 1
fi
if ! grep -Fq '48ULL <=' <<<"$ascii_slice_c"; then
  echo "ascii-slice predicates did not retain ASCII digit classification evidence" >&2
  exit 1
fi
if ! grep -Fq 'silt_static_ascii_slice_digit_bytes' <<<"$ascii_slice_c"; then
  echo "ascii-slice predicates did not retain static byte-backed sample evidence" >&2
  exit 1
fi

test_output="$("$silt_bin" test ascii-slice-test)"
if ! grep -Fq 'PASS [ascii-slice-test]' <<<"$test_output"; then
  echo "silt test did not run ascii-slice-test successfully" >&2
  echo "$test_output" >&2
  exit 1
fi

git diff --check
