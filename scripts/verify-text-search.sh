#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

if [ "${SILT_SKIP_CABAL_TEST:-0}" != "1" ]; then
  cabal test all
fi
cabal build exe:silt
silt_bin="$(cabal list-bin exe:silt)"

text_search_sources=(
  stdlib/core.silt
  stdlib/nat.silt
  stdlib/bytes.silt
  stdlib/text.silt
  stdlib/hosted.silt
  examples/text-search.silt
)

"$silt_bin" check "${text_search_sources[@]}" >/dev/null

for helper in \
  byte-slice-find-slice \
  byte-slice-contains-slice \
  text-find-text \
  text-contains-text; do
  if ! grep -Fq "$helper" examples/text-search.silt stdlib/bytes.silt stdlib/text.silt; then
    echo "text search evidence does not cover $helper" >&2
    exit 1
  fi
done

text_search_c="$("$silt_bin" emit-c-bundle "${text_search_sources[@]}" -- text-search-test)"
if ! grep -Fq 'silt_layout_ByteFindResult' <<<"$text_search_c"; then
  echo "text search did not retain the first-order ByteFindResult layout" >&2
  exit 1
fi
if ! grep -Fq 'for (uint64_t index_' <<<"$text_search_c"; then
  echo "text search did not lower through a length-driven search loop" >&2
  exit 1
fi
if ! grep -Fq '(*((uint8_t*)' <<<"$text_search_c"; then
  echo "text search did not load bytes through explicit byte pointers" >&2
  exit 1
fi
if ! grep -Fq '== needle_byte_' <<<"$text_search_c"; then
  echo "text search did not compare candidate bytes against needle bytes" >&2
  exit 1
fi
if ! grep -Fq 'silt_static_text_search_subject_bytes' <<<"$text_search_c"; then
  echo "text search did not retain static byte-backed subject evidence" >&2
  exit 1
fi
if ! grep -Fq '15ULL' <<<"$text_search_c"; then
  echo "text search did not retain missing-at-length evidence" >&2
  exit 1
fi

test_output="$("$silt_bin" test text-search-test)"
if ! grep -Fq 'PASS [text-search-test]' <<<"$test_output"; then
  echo "silt test did not run text-search-test successfully" >&2
  echo "$test_output" >&2
  exit 1
fi

git diff --check
