#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$script_dir/lib/verify-hosted-app.sh"

hosted_case_app=hosted-byte-search
hosted_verify_setup

hosted_byte_search_sources=(
  stdlib/core.silt
  stdlib/nat.silt
  stdlib/bytes.silt
  stdlib/text.silt
  stdlib/hosted.silt
  examples/hosted-byte-search.silt
)

require_file_contains examples/hosted-byte-search.silt 'text-contains-byte' \
  "hosted-byte-search stopped using the text byte-containment helper"
require_file_contains examples/hosted-byte-search.silt 'host-status-with-error-text' \
  "hosted-byte-search stopped using hosted status diagnostics"
"$silt_bin" check "${hosted_byte_search_sources[@]}" >/dev/null

hosted_byte_search_c="$("$silt_bin" emit-c-bundle "${hosted_byte_search_sources[@]}" -- hosted-byte-search-main)"
require_c_fragment "$hosted_byte_search_c" 'silt_host_arg_count' \
  "hosted-byte-search did not check process argument count"
require_c_fragment "$hosted_byte_search_c" 'silt_host_arg_base' \
  "hosted-byte-search did not read argument text boundaries"
require_c_fragment "$hosted_byte_search_c" 'silt_host_file_read_base' \
  "hosted-byte-search did not call the hosted file-read boundary"
require_c_fragment "$hosted_byte_search_c" 'silt_host_file_read_ok' \
  "hosted-byte-search did not observe hosted file-read status"
require_c_fragment "$hosted_byte_search_c" 'silt_layout_HostReadFileResult' \
  "hosted-byte-search did not use the hosted file-read result layout"
require_c_fragment "$hosted_byte_search_c" 'for (uint64_t index_' \
  "hosted-byte-search did not lower byte search through a length-driven loop"
require_c_fragment "$hosted_byte_search_c" '(*((uint8_t*)' \
  "hosted-byte-search did not load bytes through explicit byte pointers"
require_c_fragment "$hosted_byte_search_c" '== needle_' \
  "hosted-byte-search did not compare file bytes against the argument byte"
require_c_fragment "$hosted_byte_search_c" 'silt_static_hosted_byte_search_found_bytes' \
  "hosted-byte-search did not retain its found output text"
require_c_fragment "$hosted_byte_search_c" 'silt_static_hosted_byte_search_missing_bytes' \
  "hosted-byte-search did not retain its missing output text"
require_c_fragment "$hosted_byte_search_c" 'silt_host_put_byte(byte_' \
  "hosted-byte-search did not write result text to stdout"
require_c_fragment "$hosted_byte_search_c" 'silt_host_put_error_byte(byte_' \
  "hosted-byte-search did not write diagnostics to stderr"

"$silt_bin" build hosted-byte-search >/dev/null
tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

in_file="$tmp_dir/input.txt"
printf 'alpha\nbeta\ngamma\n' >"$in_file"

run_case found "$silt_bin" run hosted-byte-search -- "$in_file" b
expect_status found 0
expect_stdout_exact found $'found\n'
expect_stderr_exact found ""

run_case missing "$silt_bin" run hosted-byte-search -- "$in_file" z
expect_status missing 1
expect_stdout_exact missing $'missing\n'
expect_stderr_exact missing ""

run_case invalid_empty "$silt_bin" run hosted-byte-search -- "$in_file" ""
expect_status "empty byte" 4
expect_stdout_exact "empty byte" ""
expect_stderr_exact "empty byte" $'error: invalid byte\n'

run_case invalid_wide "$silt_bin" run hosted-byte-search -- "$in_file" ab
expect_status "wide byte" 4
expect_stdout_exact "wide byte" ""
expect_stderr_exact "wide byte" $'error: invalid byte\n'

run_case no_args "$silt_bin" run hosted-byte-search
expect_status "without args" 2
expect_stdout_exact "without args" ""
expect_stderr_exact "without args" $'usage: hosted-byte-search INPUT BYTE\n'

run_case extra "$silt_bin" run hosted-byte-search -- "$in_file" b ignored
expect_status "extra args" 2
expect_stdout_exact "extra args" ""
expect_stderr_exact "extra args" $'usage: hosted-byte-search INPUT BYTE\n'

run_case read_failed "$silt_bin" run hosted-byte-search -- "$tmp_dir/missing.txt" b
expect_status "read failure" 6
expect_stdout_exact "read failure" ""
expect_stderr_exact "read failure" $'error: read failed\n'

git diff --check
