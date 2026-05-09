#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

if [ "${SILT_SKIP_CABAL_TEST:-0}" != "1" ]; then
  cabal test all
fi
cabal build exe:silt
silt_bin="$(cabal list-bin exe:silt)"

text_scan_sources=(
  stdlib/core.silt
  stdlib/nat.silt
  stdlib/bytes.silt
  stdlib/text.silt
  stdlib/hosted.silt
  examples/text-scan.silt
)

"$silt_bin" check "${text_scan_sources[@]}" >/dev/null

text_scan_c="$("$silt_bin" emit-c-bundle "${text_scan_sources[@]}" -- text-scan-test)"
if ! grep -Fq 'silt_layout_ByteFindResult' <<<"$text_scan_c"; then
  echo "text scan did not retain the first-order ByteFindResult layout" >&2
  exit 1
fi
if ! grep -Fq 'silt_layout_ByteSplitFirst' <<<"$text_scan_c"; then
  echo "text scan did not retain the first-order ByteSplitFirst layout" >&2
  exit 1
fi
if ! grep -Fq 'silt_layout_TextSplitFirst' <<<"$text_scan_c"; then
  echo "text scan did not retain the first-order TextSplitFirst layout" >&2
  exit 1
fi
if ! grep -Fq 'for (uint64_t index_' <<<"$text_scan_c"; then
  echo "text scan did not lower through a length-driven loop" >&2
  exit 1
fi
if ! grep -Fq '(*((uint8_t*)' <<<"$text_scan_c"; then
  echo "text scan did not load bytes through explicit byte pointers" >&2
  exit 1
fi
if ! grep -Fq '== ((uint8_t)58u)' <<<"$text_scan_c"; then
  echo "text scan did not compare loaded bytes against the needle" >&2
  exit 1
fi
if ! grep -Fq 'silt_static_text_find_subject_bytes' <<<"$text_scan_c"; then
  echo "text scan did not retain static byte-backed sample evidence" >&2
  exit 1
fi
if ! grep -Fq '7ULL' <<<"$text_scan_c"; then
  echo "text scan did not retain not-found index-at-length evidence" >&2
  exit 1
fi
if ! grep -Fq '+ 1ULL) * 1ULL)' <<<"$text_scan_c"; then
  echo "text scan did not compute split-after views past the delimiter" >&2
  exit 1
fi
if ! grep -Fq '(5ULL * 1ULL)' <<<"$text_scan_c"; then
  echo "text scan did not retain split-after base evidence for delimiter exclusion" >&2
  exit 1
fi

test_output="$("$silt_bin" test text-scan-test)"
if ! grep -Fq 'PASS [text-scan-test]' <<<"$test_output"; then
  echo "silt test did not run text-scan-test successfully" >&2
  echo "$test_output" >&2
  exit 1
fi

git diff --check
