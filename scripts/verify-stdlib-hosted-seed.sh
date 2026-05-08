#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

if [ "${SILT_SKIP_CABAL_TEST:-0}" != "1" ]; then
  cabal test all
fi
cabal build exe:silt
silt_bin="$(cabal list-bin exe:silt)"
stdlib_sources=(stdlib/core.silt stdlib/nat.silt stdlib/bytes.silt stdlib/text.silt stdlib/hosted.silt examples/hosted-hello.silt test/fixtures/stdlib/stdlib-tests.silt)

"$silt_bin" check "${stdlib_sources[@]}" >/dev/null

option_sample="$("$silt_bin" norm "${stdlib_sources[@]}" -- stdlib-option-sample)"
result_sample="$("$silt_bin" norm "${stdlib_sources[@]}" -- stdlib-result-sample)"
list_sample="$("$silt_bin" norm "${stdlib_sources[@]}" -- stdlib-list-sample)"
text_len_sample="$("$silt_bin" norm "${stdlib_sources[@]}" -- stdlib-text-len-sample)"
nat_word_sample="$("$silt_bin" norm "${stdlib_sources[@]}" -- stdlib-nat-word-sample)"

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
if [ "$nat_word_sample" != "(u64 3)" ]; then
  echo "unexpected stdlib-nat-word-sample normalization: $nat_word_sample" >&2
  exit 1
fi

hosted_hello_c="$("$silt_bin" emit-c-bundle "${stdlib_sources[@]}" -- hosted-hello-main)"
if ! grep -q 'for (uint64_t index_' <<<"$hosted_hello_c"; then
  echo "hosted-hello did not lower text output to a length-driven loop" >&2
  exit 1
fi
if ! grep -q 'silt_host_put_byte(byte_' <<<"$hosted_hello_c"; then
  echo "hosted-hello did not call the hosted byte output boundary" >&2
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
