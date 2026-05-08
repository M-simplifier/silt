#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

if [ "${SILT_SKIP_CABAL_TEST:-0}" != "1" ]; then
  cabal test all
fi
cabal build exe:silt
silt_bin="$(cabal list-bin exe:silt)"

"$silt_bin" check \
  stdlib/core.silt \
  stdlib/bytes.silt \
  stdlib/text.silt \
  stdlib/hosted.silt \
  examples/hosted-hello.silt \
  test/fixtures/stdlib/stdlib-tests.silt >/dev/null

option_sample="$("$silt_bin" norm stdlib/core.silt stdlib/bytes.silt stdlib/text.silt stdlib/hosted.silt examples/hosted-hello.silt test/fixtures/stdlib/stdlib-tests.silt -- stdlib-option-sample)"
result_sample="$("$silt_bin" norm stdlib/core.silt stdlib/bytes.silt stdlib/text.silt stdlib/hosted.silt examples/hosted-hello.silt test/fixtures/stdlib/stdlib-tests.silt -- stdlib-result-sample)"
list_sample="$("$silt_bin" norm stdlib/core.silt stdlib/bytes.silt stdlib/text.silt stdlib/hosted.silt examples/hosted-hello.silt test/fixtures/stdlib/stdlib-tests.silt -- stdlib-list-sample)"
text_len_sample="$("$silt_bin" norm stdlib/core.silt stdlib/bytes.silt stdlib/text.silt stdlib/hosted.silt examples/hosted-hello.silt test/fixtures/stdlib/stdlib-tests.silt -- stdlib-text-len-sample)"

if [ "$option_sample" != "(u64 42)" ]; then
  echo "unexpected stdlib-option-sample normalization: $option_sample" >&2
  exit 1
fi
if [ "$result_sample" != "(u64 7)" ]; then
  echo "unexpected stdlib-result-sample normalization: $result_sample" >&2
  exit 1
fi
if [ "$list_sample" != "(u64 9)" ]; then
  echo "unexpected stdlib-list-sample normalization: $list_sample" >&2
  exit 1
fi
if [ "$text_len_sample" != "(u64 5)" ]; then
  echo "unexpected stdlib-text-len-sample normalization: $text_len_sample" >&2
  exit 1
fi

"$silt_bin" build hosted-hello >/dev/null
hello_output="$("$silt_bin" run hosted-hello)"
if [ "$hello_output" != "SILT" ]; then
  echo "unexpected hosted-hello output: $hello_output" >&2
  exit 1
fi

"$silt_bin" test >/dev/null
git diff --check
