#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

if [ "${SILT_SKIP_CABAL_TEST:-0}" != "1" ]; then
  cabal test all
fi
cabal build exe:silt
silt_bin="$(cabal list-bin exe:silt)"

ascii_decimal_format_sources=(
  stdlib/core.silt
  stdlib/nat.silt
  stdlib/bytes.silt
  stdlib/text.silt
  stdlib/ascii.silt
  stdlib/ascii-decimal.silt
  stdlib/hosted.silt
  examples/ascii-decimal-u64-format.silt
)

"$silt_bin" check "${ascii_decimal_format_sources[@]}" >/dev/null

ascii_decimal_format_c="$("$silt_bin" emit-c-bundle "${ascii_decimal_format_sources[@]}" -- ascii-decimal-u64-format-test)"
if ! grep -Fq 'for (uint64_t index_' <<<"$ascii_decimal_format_c"; then
  echo "ascii decimal formatter did not lower through a fixed loop" >&2
  exit 1
fi
if ! grep -Fq '% 10ULL' <<<"$ascii_decimal_format_c"; then
  echo "ascii decimal formatter did not retain decimal digit remainder evidence" >&2
  exit 1
fi
if ! grep -Fq '/ 10ULL' <<<"$ascii_decimal_format_c"; then
  echo "ascii decimal formatter did not retain decimal quotient evidence" >&2
  exit 1
fi
if ! grep -Eq '\*\(\(uint8_t\*\).*silt_cell_ascii_decimal_format_max_buffer\[0\].*= \(\(uint8_t\)\(\(48ULL \+.*% 10ULL' <<<"$ascii_decimal_format_c"; then
  echo "ascii decimal formatter did not write ASCII digits into the caller-provided max-value buffer" >&2
  exit 1
fi
if ! grep -Fq '48ULL +' <<<"$ascii_decimal_format_c"; then
  echo "ascii decimal formatter did not retain ASCII digit offset evidence" >&2
  exit 1
fi
if ! grep -Fq '< 20ULL' <<<"$ascii_decimal_format_c"; then
  echo "ascii decimal formatter did not retain its fixed-capacity state guard" >&2
  exit 1
fi
if ! grep -Fq 'silt_static_ascii_decimal_format_max_bytes' <<<"$ascii_decimal_format_c"; then
  echo "ascii decimal formatter did not retain max-value expected text evidence" >&2
  exit 1
fi
if ! grep -Fq 'silt_cell_ascii_decimal_format_max_buffer' <<<"$ascii_decimal_format_c"; then
  echo "ascii decimal formatter did not retain caller-provided buffer evidence" >&2
  exit 1
fi

test_output="$("$silt_bin" test ascii-decimal-u64-format-test)"
if ! grep -Fq 'PASS [ascii-decimal-u64-format-test]' <<<"$test_output"; then
  echo "silt test did not run ascii-decimal-u64-format-test successfully" >&2
  echo "$test_output" >&2
  exit 1
fi

git diff --check
