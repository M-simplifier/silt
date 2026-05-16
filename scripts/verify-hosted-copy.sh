#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$script_dir/lib/verify-hosted-app.sh"

hosted_case_app=hosted-copy
hosted_verify_setup

hosted_copy_sources=(
  stdlib/core.silt
  stdlib/nat.silt
  stdlib/bytes.silt
  stdlib/text.silt
  stdlib/hosted.silt
  examples/hosted-copy.silt
)

require_file_contains examples/hosted-copy.silt 'host-read-file-result' \
  "hosted-copy stopped using the hosted file-read result layout"
require_file_contains examples/hosted-copy.silt 'host-write-file' \
  "hosted-copy stopped using the hosted file-write boundary"
require_file_contains examples/hosted-copy.silt 'host-status-with-error-text' \
  "hosted-copy stopped using hosted status diagnostics"
"$silt_bin" check "${hosted_copy_sources[@]}" >/dev/null

hosted_copy_c="$("$silt_bin" emit-c-bundle "${hosted_copy_sources[@]}" -- hosted-copy-main)"
require_c_fragment "$hosted_copy_c" 'silt_host_arg_count' \
  "hosted-copy did not check process argument count"
require_c_fragment "$hosted_copy_c" 'silt_host_arg_base' \
  "hosted-copy did not read argument text boundaries"
require_c_fragment "$hosted_copy_c" 'silt_host_file_read_base' \
  "hosted-copy did not call the hosted file-read boundary"
require_c_fragment "$hosted_copy_c" 'silt_host_file_read_ok' \
  "hosted-copy did not observe hosted file-read status"
require_c_fragment "$hosted_copy_c" 'silt_layout_HostReadFileResult' \
  "hosted-copy did not use the hosted file-read result layout"
require_c_fragment "$hosted_copy_c" 'silt_host_file_write_bytes' \
  "hosted-copy did not call the hosted file-write boundary"
require_c_fragment "$hosted_copy_c" 'silt_host_put_error_byte(byte_' \
  "hosted-copy did not write diagnostics to stderr"

"$silt_bin" build hosted-copy >/dev/null
tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

input_file="$tmp_dir/input.bin"
output_file="$tmp_dir/output.bin"
printf 'alpha\0beta\nSILT\n' >"$input_file"
run_case copy "$silt_bin" run hosted-copy -- "$input_file" "$output_file"
expect_status success 0
expect_stdout_exact copy ""
expect_stderr_exact copy ""
if ! cmp -s "$input_file" "$output_file"; then
  fail_verify "hosted-copy did not preserve copied bytes"
fi

printf 'stale output\n' >"$output_file"
run_case overwrite "$silt_bin" run hosted-copy -- "$input_file" "$output_file"
expect_status overwrite 0
expect_stdout_exact overwrite ""
expect_stderr_exact overwrite ""
if ! cmp -s "$input_file" "$output_file"; then
  fail_verify "hosted-copy did not overwrite existing output with copied bytes"
fi

empty_input="$tmp_dir/empty.bin"
empty_output="$tmp_dir/empty-output.bin"
: >"$empty_input"
run_case empty "$silt_bin" run hosted-copy -- "$empty_input" "$empty_output"
expect_status empty 0
expect_stdout_exact empty ""
expect_stderr_exact empty ""
if ! cmp -s "$empty_input" "$empty_output"; then
  fail_verify "hosted-copy did not preserve an empty input"
fi

run_case missing "$silt_bin" run hosted-copy
expect_status "without args" 2
expect_stdout_exact missing-args ""
expect_stderr_exact missing-args $'usage: hosted-copy INPUT OUTPUT\n'

extra_out="$tmp_dir/extra.txt"
run_case extra "$silt_bin" run hosted-copy -- "$input_file" "$extra_out" ignored
expect_status "extra args" 2
expect_stdout_exact extra-args ""
expect_stderr_exact extra-args $'usage: hosted-copy INPUT OUTPUT\n'
expect_file_absent "extra args" "$extra_out"

read_failed_out="$tmp_dir/read-failed.txt"
run_case read_failed "$silt_bin" run hosted-copy -- "$tmp_dir/missing-input.txt" "$read_failed_out"
expect_status "missing input" 6
expect_stdout_exact read-failure ""
expect_stderr_exact read-failure $'error: read failed\n'
expect_file_absent "read failure" "$read_failed_out"

run_case write_failed "$silt_bin" run hosted-copy -- "$input_file" "$tmp_dir/nope/output.txt"
expect_status "write failure" 3
expect_stdout_exact write-failure ""
expect_stderr_exact write-failure $'error: write failed\n'

git diff --check
