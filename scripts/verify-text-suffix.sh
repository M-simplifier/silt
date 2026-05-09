#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

if [ "${SILT_SKIP_CABAL_TEST:-0}" != "1" ]; then
  cabal test all
fi
cabal build exe:silt
silt_bin="$(cabal list-bin exe:silt)"

text_suffix_sources=(
  stdlib/core.silt
  stdlib/nat.silt
  stdlib/bytes.silt
  stdlib/text.silt
  stdlib/hosted.silt
  examples/text-suffix.silt
)

"$silt_bin" check "${text_suffix_sources[@]}" >/dev/null

text_suffix_c="$("$silt_bin" emit-c-bundle "${text_suffix_sources[@]}" -- text-suffix-test)"
if ! grep -Fq 'for (uint64_t index_' <<<"$text_suffix_c"; then
  echo "text-suffix did not lower suffix equality through a length-driven loop" >&2
  exit 1
fi
if ! grep -Fq '(*((uint8_t*)' <<<"$text_suffix_c"; then
  echo "text-suffix did not load bytes through explicit byte pointers" >&2
  exit 1
fi
if ! grep -Fq '== right_byte_' <<<"$text_suffix_c"; then
  echo "text-suffix did not compare loaded bytes" >&2
  exit 1
fi
if ! grep -Fq 'silt_static_text_suffix_subject_bytes' <<<"$text_suffix_c"; then
  echo "text-suffix did not retain static byte-backed text evidence" >&2
  exit 1
fi

test_output="$("$silt_bin" test text-suffix-test)"
if ! grep -Fq 'PASS [text-suffix-test]' <<<"$test_output"; then
  echo "silt test did not run text-suffix-test successfully" >&2
  echo "$test_output" >&2
  exit 1
fi

git diff --check
