#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$script_dir/lib/verify-hosted-app.sh"

hosted_case_app=hosted-size-report
hosted_verify_setup

hosted_size_report_sources=(
  stdlib/core.silt
  stdlib/nat.silt
  stdlib/bytes.silt
  stdlib/text.silt
  stdlib/ascii.silt
  stdlib/ascii-decimal.silt
  stdlib/hosted.silt
  stdlib/hosted-decimal.silt
  examples/hosted-size-report.silt
)

require_file_contains examples/hosted-size-report.silt 'host-status-with-error-text' \
  "hosted-size-report stopped using hosted status diagnostics"
require_file_contains examples/hosted-size-report.silt 'host-write-file-u64-decimal' \
  "hosted-size-report stopped using decimal file output"
require_file_contains examples/hosted-size-report.silt 'host-write-u64-decimal' \
  "hosted-size-report stopped using decimal stdout output"
"$silt_bin" check "${hosted_size_report_sources[@]}" >/dev/null

hosted_size_report_c="$("$silt_bin" emit-c-bundle "${hosted_size_report_sources[@]}" -- hosted-size-report-main)"
require_c_fragment "$hosted_size_report_c" 'silt_host_arg_count' \
  "hosted-size-report did not check process argument count"
require_c_fragment "$hosted_size_report_c" 'silt_host_arg_base' \
  "hosted-size-report did not read argument text boundaries"
require_c_fragment "$hosted_size_report_c" 'silt_host_file_read_base' \
  "hosted-size-report did not call the hosted file-read boundary"
require_c_fragment "$hosted_size_report_c" 'silt_host_file_read_len' \
  "hosted-size-report did not retain hosted file-read length evidence"
require_c_fragment "$hosted_size_report_c" 'silt_host_file_read_ok' \
  "hosted-size-report did not observe hosted file-read status"
require_c_fragment "$hosted_size_report_c" 'silt_layout_HostReadFileResult' \
  "hosted-size-report did not use the hosted file-read result layout"
require_c_fragment "$hosted_size_report_c" 'silt_host_file_write_bytes' \
  "hosted-size-report did not call the hosted file-write boundary"
require_c_fragment "$hosted_size_report_c" 'silt_host_put_byte(byte_' \
  "hosted-size-report did not write formatted output to stdout"
require_c_fragment "$hosted_size_report_c" 'silt_host_put_error_byte(byte_' \
  "hosted-size-report did not write diagnostics to stderr"
require_c_fragment "$hosted_size_report_c" '* 10ULL) + (((uint64_t)byte_' \
  "hosted-size-report did not retain decimal parse accumulation evidence"
require_c_fragment "$hosted_size_report_c" '% 10ULL' \
  "hosted-size-report did not retain decimal format remainder evidence"
require_c_fragment "$hosted_size_report_c" '/ 10ULL' \
  "hosted-size-report did not retain decimal format division evidence"
require_c_fragment "$hosted_size_report_c" 'silt_cell_hosted_size_report_file_buffer' \
  "hosted-size-report did not retain its file-output formatting buffer"
require_c_fragment "$hosted_size_report_c" 'silt_cell_hosted_size_report_stdout_buffer' \
  "hosted-size-report did not retain its stdout formatting buffer"

"$silt_bin" build hosted-size-report >/dev/null
tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT
in_file="$tmp_dir/input.txt"
out_file="$tmp_dir/out.txt"
printf 'SILT_APP' > "$in_file"

run_case ok "$silt_bin" run hosted-size-report -- "$in_file" 8 "$out_file"
expect_status success 0
expect_stdout_exact success "8"
expect_stderr_exact success ""
expect_file_exact success "$out_file" "8"

empty_file="$tmp_dir/empty.txt"
empty_out="$tmp_dir/empty-out.txt"
: > "$empty_file"
run_case empty "$silt_bin" run hosted-size-report -- "$empty_file" 0 "$empty_out"
expect_status empty-file 0
expect_stdout_exact empty-file "0"
expect_stderr_exact empty-file ""
expect_file_exact empty-file "$empty_out" "0"

mismatch_out="$tmp_dir/mismatch.txt"
run_case mismatch "$silt_bin" run hosted-size-report -- "$in_file" 9 "$mismatch_out"
expect_status mismatch 5
expect_stdout_exact mismatch "8"
expect_stderr_exact mismatch $'error: length mismatch\n'
expect_file_exact mismatch "$mismatch_out" "8"

invalid_out="$tmp_dir/invalid.txt"
run_case invalid "$silt_bin" run hosted-size-report -- "$in_file" nope "$invalid_out"
expect_status "invalid expected length" 4
expect_stdout_exact "invalid expected" ""
expect_stderr_exact "invalid expected" $'error: invalid expected length\n'
expect_file_absent "invalid expected length" "$invalid_out"

run_case missing "$silt_bin" run hosted-size-report
expect_status "without args" 2
expect_stdout_exact missing-args ""
expect_stderr_exact missing-args $'usage: hosted-size-report INPUT EXPECTED_LEN OUTPUT\n'

extra_out="$tmp_dir/extra.txt"
run_case extra "$silt_bin" run hosted-size-report -- "$in_file" 8 "$extra_out" ignored
expect_status "extra args" 2
expect_stdout_exact extra-args ""
expect_stderr_exact extra-args $'usage: hosted-size-report INPUT EXPECTED_LEN OUTPUT\n'
expect_file_absent "extra args" "$extra_out"

read_failed_out="$tmp_dir/read-failed.txt"
run_case read_failed "$silt_bin" run hosted-size-report -- "$tmp_dir/missing-input.txt" 0 "$read_failed_out"
expect_status "missing input" 6
expect_stdout_exact read-failure ""
expect_stderr_exact read-failure $'error: read failed\n'
expect_file_absent "read failure" "$read_failed_out"

run_case write_failed "$silt_bin" run hosted-size-report -- "$in_file" 8 "$tmp_dir/nope/out.txt"
expect_status "write failure" 3
expect_stdout_exact write-failure ""
expect_stderr_exact write-failure $'error: write failed\n'

git diff --check
