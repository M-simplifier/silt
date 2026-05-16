#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$script_dir/lib/verify-hosted-app.sh"

hosted_case_app=hosted-text-search
hosted_verify_setup

hosted_text_search_sources=(
  stdlib/core.silt
  stdlib/nat.silt
  stdlib/bytes.silt
  stdlib/text.silt
  stdlib/hosted.silt
  examples/hosted-text-search.silt
)

require_file_contains examples/hosted-text-search.silt 'text-contains-text' \
  "hosted-text-search stopped using the text substring-containment helper"
require_file_contains examples/hosted-text-search.silt 'host-status-with-error-text' \
  "hosted-text-search stopped using hosted status diagnostics"
"$silt_bin" check "${hosted_text_search_sources[@]}" >/dev/null

hosted_text_search_c="$("$silt_bin" emit-c-bundle "${hosted_text_search_sources[@]}" -- hosted-text-search-main)"
require_c_fragment "$hosted_text_search_c" 'silt_host_arg_count' \
  "hosted-text-search did not check process argument count"
require_c_fragment "$hosted_text_search_c" 'silt_host_arg_base' \
  "hosted-text-search did not read argument text boundaries"
require_c_fragment "$hosted_text_search_c" 'silt_host_file_read_base' \
  "hosted-text-search did not call the hosted file-read boundary"
require_c_fragment "$hosted_text_search_c" 'silt_host_file_read_ok' \
  "hosted-text-search did not observe hosted file-read status"
require_c_fragment "$hosted_text_search_c" 'silt_layout_HostReadFileResult' \
  "hosted-text-search did not use the hosted file-read result layout"
require_c_fragment "$hosted_text_search_c" 'for (uint64_t index_' \
  "hosted-text-search did not lower substring search through a length-driven loop"
require_c_fragment "$hosted_text_search_c" '(*((uint8_t*)' \
  "hosted-text-search did not load bytes through explicit byte pointers"
require_c_fragment "$hosted_text_search_c" '== needle_byte_' \
  "hosted-text-search did not compare file bytes against needle bytes"
require_c_fragment "$hosted_text_search_c" 'silt_static_hosted_text_search_found_bytes' \
  "hosted-text-search did not retain its found output text"
require_c_fragment "$hosted_text_search_c" 'silt_static_hosted_text_search_missing_bytes' \
  "hosted-text-search did not retain its missing output text"
require_c_fragment "$hosted_text_search_c" 'silt_host_put_byte(byte_' \
  "hosted-text-search did not write result text to stdout"
require_c_fragment "$hosted_text_search_c" 'silt_host_put_error_byte(byte_' \
  "hosted-text-search did not write diagnostics to stderr"

"$silt_bin" build hosted-text-search >/dev/null
tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

in_file="$tmp_dir/input.txt"
printf 'alpha\nbeta\ngamma\n' >"$in_file"

run_case found "$silt_bin" run hosted-text-search -- "$in_file" beta
expect_status found 0
expect_stdout_exact found $'found\n'
expect_stderr_exact found ""

run_case missing "$silt_bin" run hosted-text-search -- "$in_file" delta
expect_status missing 1
expect_stdout_exact missing $'missing\n'
expect_stderr_exact missing ""

run_case empty "$silt_bin" run hosted-text-search -- "$in_file" ""
expect_status "empty needle" 4
expect_stdout_exact "empty needle" ""
expect_stderr_exact "empty needle" $'error: empty needle\n'

run_case no_args "$silt_bin" run hosted-text-search
expect_status "without args" 2
expect_stdout_exact "without args" ""
expect_stderr_exact "without args" $'usage: hosted-text-search INPUT NEEDLE\n'

run_case extra "$silt_bin" run hosted-text-search -- "$in_file" beta ignored
expect_status "extra args" 2
expect_stdout_exact "extra args" ""
expect_stderr_exact "extra args" $'usage: hosted-text-search INPUT NEEDLE\n'

run_case read_failed "$silt_bin" run hosted-text-search -- "$tmp_dir/missing.txt" beta
expect_status "read failure" 6
expect_stdout_exact "read failure" ""
expect_stderr_exact "read failure" $'error: read failed\n'

git diff --check
