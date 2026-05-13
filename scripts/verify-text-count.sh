#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

if [ "${SILT_SKIP_CABAL_TEST:-0}" != "1" ]; then
  cabal test all
fi
cabal build exe:silt
silt_bin="$(cabal list-bin exe:silt)"

text_count_sources=(
  stdlib/core.silt
  stdlib/nat.silt
  stdlib/bytes.silt
  stdlib/text.silt
  stdlib/hosted.silt
  examples/text-count.silt
)

"$silt_bin" check "${text_count_sources[@]}" >/dev/null

for helper in \
  byte-slice-count-byte \
  byte-slice-count-lf \
  text-count-byte \
  text-count-lf; do
  if ! grep -Fq "$helper" examples/text-count.silt; then
    echo "text count example does not exercise $helper" >&2
    exit 1
  fi
done

text_count_c="$("$silt_bin" emit-c-bundle "${text_count_sources[@]}" -- text-count-test)"
if ! grep -Fq 'for (uint64_t index_' <<<"$text_count_c"; then
  echo "text count did not lower through a length-driven loop" >&2
  exit 1
fi
if ! grep -Fq '(*((uint8_t*)' <<<"$text_count_c"; then
  echo "text count did not load bytes through explicit byte pointers" >&2
  exit 1
fi
if ! grep -Fq '== ((uint8_t)10u)' <<<"$text_count_c"; then
  echo "text count did not compare loaded bytes against LF" >&2
  exit 1
fi
if ! grep -Fq '== ((uint8_t)65u)' <<<"$text_count_c"; then
  echo "text count did not compare loaded bytes against a non-LF needle" >&2
  exit 1
fi
if ! grep -Fq 'silt_static_text_count_many_bytes' <<<"$text_count_c"; then
  echo "text count did not retain static multi-hit byte evidence" >&2
  exit 1
fi

test_output="$("$silt_bin" test text-count-test)"
if ! grep -Fq 'PASS [text-count-test]' <<<"$test_output"; then
  echo "silt test did not run text-count-test successfully" >&2
  echo "$test_output" >&2
  exit 1
fi

git diff --check
