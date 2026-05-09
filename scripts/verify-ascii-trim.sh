#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

if [ "${SILT_SKIP_CABAL_TEST:-0}" != "1" ]; then
  cabal test all
fi
cabal build exe:silt
silt_bin="$(cabal list-bin exe:silt)"

ascii_trim_sources=(
  stdlib/core.silt
  stdlib/nat.silt
  stdlib/bytes.silt
  stdlib/text.silt
  stdlib/ascii.silt
  stdlib/ascii-slice.silt
  stdlib/ascii-decimal.silt
  stdlib/hosted.silt
  examples/ascii-trim.silt
)

"$silt_bin" check "${ascii_trim_sources[@]}" >/dev/null

ascii_trim_c="$("$silt_bin" emit-c-bundle "${ascii_trim_sources[@]}" -- ascii-trim-test)"
if ! grep -Fq 'silt_layout_AsciiTrimState' <<<"$ascii_trim_c"; then
  echo "ASCII trim did not retain the first-order AsciiTrimState layout" >&2
  exit 1
fi
if ! grep -Fq 'for (uint64_t index_' <<<"$ascii_trim_c"; then
  echo "ASCII trim did not lower through a length-driven loop" >&2
  exit 1
fi
if ! grep -Fq '(*((uint8_t*)' <<<"$ascii_trim_c"; then
  echo "ASCII trim did not load bytes through explicit byte pointers" >&2
  exit 1
fi
if ! grep -Fq '9ULL <=' <<<"$ascii_trim_c"; then
  echo "ASCII trim did not retain ASCII whitespace lower-bound evidence" >&2
  exit 1
fi
if ! grep -Fq '13ULL' <<<"$ascii_trim_c"; then
  echo "ASCII trim did not retain ASCII whitespace upper-bound evidence" >&2
  exit 1
fi
if ! grep -Fq '== ((uint8_t)32u)' <<<"$ascii_trim_c"; then
  echo "ASCII trim did not retain ASCII space evidence" >&2
  exit 1
fi
if ! grep -Fq 'silt_static_ascii_trim_subject_bytes' <<<"$ascii_trim_c"; then
  echo "ASCII trim did not retain static byte-backed sample evidence" >&2
  exit 1
fi
if ! grep -Fq 'silt_static_ascii_trim_leading_bytes' <<<"$ascii_trim_c"; then
  echo "ASCII trim did not retain leading-only sample evidence" >&2
  exit 1
fi
if ! grep -Fq 'silt_static_ascii_trim_trailing_bytes' <<<"$ascii_trim_c"; then
  echo "ASCII trim did not retain trailing-only sample evidence" >&2
  exit 1
fi
if ! grep -Fq 'silt_static_ascii_trim_interior_bytes' <<<"$ascii_trim_c"; then
  echo "ASCII trim did not retain interior-whitespace sample evidence" >&2
  exit 1
fi
if ! grep -Fq 'silt_static_ascii_trim_non_ascii_bytes' <<<"$ascii_trim_c"; then
  echo "ASCII trim did not retain non-ASCII sample evidence" >&2
  exit 1
fi
if ! grep -Fq '(2ULL * 1ULL)' <<<"$ascii_trim_c"; then
  echo "ASCII trim did not retain trimmed start-offset evidence" >&2
  exit 1
fi
if ! grep -Fq '(3ULL * 1ULL)' <<<"$ascii_trim_c"; then
  echo "ASCII trim did not retain all-whitespace end-offset evidence" >&2
  exit 1
fi
if ! grep -Fq '42ULL' <<<"$ascii_trim_c"; then
  echo "ASCII trim did not retain trim-before-parse value evidence" >&2
  exit 1
fi

test_output="$("$silt_bin" test ascii-trim-test)"
if ! grep -Fq 'PASS [ascii-trim-test]' <<<"$test_output"; then
  echo "silt test did not run ascii-trim-test successfully" >&2
  echo "$test_output" >&2
  exit 1
fi

git diff --check
