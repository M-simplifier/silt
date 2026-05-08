#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

if [ "${SILT_SKIP_CABAL_TEST:-0}" != "1" ]; then
  cabal test all
fi
cabal build exe:silt
silt_bin="$(cabal list-bin exe:silt)"

text_eq_sources=(
  stdlib/core.silt
  stdlib/nat.silt
  stdlib/bytes.silt
  stdlib/text.silt
  stdlib/hosted.silt
  examples/text-eq.silt
)

"$silt_bin" check "${text_eq_sources[@]}" >/dev/null

text_eq_c="$("$silt_bin" emit-c-bundle "${text_eq_sources[@]}" -- text-eq-test)"
if ! grep -Fq 'for (uint64_t index_' <<<"$text_eq_c"; then
  echo "text-eq did not lower byte equality through a length-driven loop" >&2
  exit 1
fi
if ! grep -Fq '(*((uint8_t*)' <<<"$text_eq_c"; then
  echo "text-eq did not load bytes through explicit byte pointers" >&2
  exit 1
fi
if ! grep -Fq '== right_byte_' <<<"$text_eq_c"; then
  echo "text-eq did not compare loaded bytes" >&2
  exit 1
fi
if ! grep -Fq 'silt_static_text_eq_left_bytes' <<<"$text_eq_c"; then
  echo "text-eq did not retain static byte-backed text evidence" >&2
  exit 1
fi

test_output="$("$silt_bin" test text-eq-test)"
if ! grep -Fq 'PASS [text-eq-test]' <<<"$test_output"; then
  echo "silt test did not run text-eq-test successfully" >&2
  echo "$test_output" >&2
  exit 1
fi

git diff --check
