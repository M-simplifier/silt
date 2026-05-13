#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

if [ "${SILT_SKIP_CABAL_TEST:-0}" != "1" ]; then
  cabal test all
fi
cabal build exe:silt
silt_bin="$(cabal list-bin exe:silt)"

text_line_sources=(
  stdlib/core.silt
  stdlib/nat.silt
  stdlib/bytes.silt
  stdlib/text.silt
  stdlib/hosted.silt
  examples/text-lines.silt
)

"$silt_bin" check "${text_line_sources[@]}" >/dev/null

if ! grep -Fq 'byte-slice-split-first-lf' examples/text-lines.silt; then
  echo "text line example does not exercise byte-slice-split-first-lf" >&2
  exit 1
fi
if ! grep -Fq 'text-split-first-lf' examples/text-lines.silt; then
  echo "text line example does not exercise text-split-first-lf" >&2
  exit 1
fi

text_line_c="$("$silt_bin" emit-c-bundle "${text_line_sources[@]}" -- text-line-test)"
if ! grep -Fq 'silt_layout_ByteSplitFirst' <<<"$text_line_c"; then
  echo "text line split did not retain the first-order ByteSplitFirst layout" >&2
  exit 1
fi
if ! grep -Fq 'silt_layout_TextSplitFirst' <<<"$text_line_c"; then
  echo "text line split did not retain the first-order TextSplitFirst layout" >&2
  exit 1
fi
if ! grep -Fq '== ((uint8_t)10u)' <<<"$text_line_c"; then
  echo "text line split did not compare loaded bytes against LF" >&2
  exit 1
fi
if ! grep -Fq 'silt_static_text_line_two_bytes' <<<"$text_line_c"; then
  echo "text line split did not retain static two-line byte evidence" >&2
  exit 1
fi
if ! grep -Fq '+ 1ULL) * 1ULL)' <<<"$text_line_c"; then
  echo "text line split did not compute split-after views past LF" >&2
  exit 1
fi
if ! grep -Fq '(4ULL * 1ULL)' <<<"$text_line_c"; then
  echo "text line split did not retain split-after base evidence for LF exclusion" >&2
  exit 1
fi

test_output="$("$silt_bin" test text-line-test)"
if ! grep -Fq 'PASS [text-line-test]' <<<"$test_output"; then
  echo "silt test did not run text-line-test successfully" >&2
  echo "$test_output" >&2
  exit 1
fi

git diff --check
