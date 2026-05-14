#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$script_dir/lib/verify-hosted-app.sh"

hosted_case_app=hosted-lf-count
hosted_verify_setup

hosted_lf_count_sources=(
  stdlib/core.silt
  stdlib/nat.silt
  stdlib/bytes.silt
  stdlib/text.silt
  stdlib/ascii.silt
  stdlib/ascii-decimal.silt
  stdlib/hosted.silt
  stdlib/hosted-decimal.silt
  examples/hosted-lf-count.silt
)

require_file_contains examples/hosted-lf-count.silt 'text-count-lf' \
  "hosted-lf-count stopped using the text LF counter"
require_file_contains examples/hosted-lf-count.silt 'host-status-with-error-text' \
  "hosted-lf-count stopped using hosted status diagnostics"
require_file_contains examples/hosted-lf-count.silt 'host-write-file-u64-decimal' \
  "hosted-lf-count stopped using decimal file output"
require_file_contains examples/hosted-lf-count.silt 'host-write-u64-decimal' \
  "hosted-lf-count stopped using decimal stdout output"
"$silt_bin" check "${hosted_lf_count_sources[@]}" >/dev/null

hosted_lf_count_c="$("$silt_bin" emit-c-bundle "${hosted_lf_count_sources[@]}" -- hosted-lf-count-main)"
require_c_fragment "$hosted_lf_count_c" 'silt_host_arg_count' \
  "hosted-lf-count did not check process argument count"
require_c_fragment "$hosted_lf_count_c" 'silt_host_arg_base' \
  "hosted-lf-count did not read argument text boundaries"
require_c_fragment "$hosted_lf_count_c" 'silt_host_file_read_base' \
  "hosted-lf-count did not call the hosted file-read boundary"
require_c_fragment "$hosted_lf_count_c" 'silt_host_file_read_ok' \
  "hosted-lf-count did not observe hosted file-read status"
require_c_fragment "$hosted_lf_count_c" 'silt_layout_HostReadFileResult' \
  "hosted-lf-count did not use the hosted file-read result layout"
require_c_fragment "$hosted_lf_count_c" 'for (uint64_t index_' \
  "hosted-lf-count did not lower the LF count through a length-driven loop"
require_c_fragment "$hosted_lf_count_c" '(*((uint8_t*)' \
  "hosted-lf-count did not load bytes through explicit byte pointers"
require_c_fragment "$hosted_lf_count_c" '== ((uint8_t)10u)' \
  "hosted-lf-count did not compare loaded bytes against LF"
require_c_fragment "$hosted_lf_count_c" 'silt_host_file_write_bytes' \
  "hosted-lf-count did not call the hosted file-write boundary"
require_c_fragment "$hosted_lf_count_c" 'silt_host_put_byte(byte_' \
  "hosted-lf-count did not write formatted output to stdout"
require_c_fragment "$hosted_lf_count_c" 'silt_host_put_error_byte(byte_' \
  "hosted-lf-count did not write diagnostics to stderr"
require_c_fragment "$hosted_lf_count_c" '% 10ULL' \
  "hosted-lf-count did not retain decimal format remainder evidence"
require_c_fragment "$hosted_lf_count_c" '/ 10ULL' \
  "hosted-lf-count did not retain decimal format division evidence"
require_c_fragment "$hosted_lf_count_c" 'silt_cell_hosted_lf_count_file_buffer' \
  "hosted-lf-count did not retain its file-output formatting buffer"
require_c_fragment "$hosted_lf_count_c" 'silt_cell_hosted_lf_count_stdout_buffer' \
  "hosted-lf-count did not retain its stdout formatting buffer"

"$silt_bin" build hosted-lf-count >/dev/null
tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

lf_file="$tmp_dir/lf.txt"
lf_out="$tmp_dir/lf-out.txt"
printf 'alpha\nbeta\ngamma\n' >"$lf_file"
run_case lf "$silt_bin" run hosted-lf-count -- "$lf_file" "$lf_out"
expect_status success 0
expect_stdout_exact lf "3"
expect_stderr_exact lf ""
expect_file_exact "LF count" "$lf_out" "3"

none_file="$tmp_dir/no-lf.txt"
none_out="$tmp_dir/no-lf-out.txt"
printf 'no newline here' >"$none_file"
run_case no_lf "$silt_bin" run hosted-lf-count -- "$none_file" "$none_out"
expect_status no-LF 0
expect_stdout_exact no-lf "0"
expect_stderr_exact no-lf ""
expect_file_exact no-LF "$none_out" "0"

run_case missing "$silt_bin" run hosted-lf-count
expect_status "without args" 2
expect_stdout_exact missing-args ""
expect_stderr_exact missing-args $'usage: hosted-lf-count INPUT OUTPUT\n'

extra_out="$tmp_dir/extra.txt"
run_case extra "$silt_bin" run hosted-lf-count -- "$lf_file" "$extra_out" ignored
expect_status "extra args" 2
expect_stdout_exact extra-args ""
expect_stderr_exact extra-args $'usage: hosted-lf-count INPUT OUTPUT\n'
expect_file_absent "extra args" "$extra_out"

read_failed_out="$tmp_dir/read-failed.txt"
run_case read_failed "$silt_bin" run hosted-lf-count -- "$tmp_dir/missing-input.txt" "$read_failed_out"
expect_status "missing input" 6
expect_stdout_exact read-failure ""
expect_stderr_exact read-failure $'error: read failed\n'
expect_file_absent "read failure" "$read_failed_out"

run_case write_failed "$silt_bin" run hosted-lf-count -- "$lf_file" "$tmp_dir/nope/out.txt"
expect_status "write failure" 3
expect_stdout_exact write-failure ""
expect_stderr_exact write-failure $'error: write failed\n'

git diff --check
