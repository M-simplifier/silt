#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$script_dir/lib/verify-hosted-app.sh"

hosted_case_app=hosted-config-report
hosted_verify_setup

hosted_config_report_sources=(
  stdlib/core.silt
  stdlib/nat.silt
  stdlib/bytes.silt
  stdlib/text.silt
  stdlib/ascii.silt
  stdlib/ascii-slice.silt
  stdlib/ascii-decimal.silt
  stdlib/hosted.silt
  stdlib/hosted-decimal.silt
  examples/hosted-config-report.silt
)

require_file_contains examples/hosted-config-report.silt 'host-status-with-error-text' \
  "hosted-config-report stopped using hosted status diagnostics"
require_file_contains examples/hosted-config-report.silt 'host-write-file-u64-decimal' \
  "hosted-config-report stopped using decimal file output"
require_file_contains examples/hosted-config-report.silt 'host-write-u64-decimal' \
  "hosted-config-report stopped using decimal stdout output"
"$silt_bin" check "${hosted_config_report_sources[@]}" >/dev/null

hosted_config_report_c="$("$silt_bin" emit-c-bundle "${hosted_config_report_sources[@]}" -- hosted-config-report-main)"
require_c_fragment "$hosted_config_report_c" 'silt_host_arg_count' \
  "hosted-config-report did not check process argument count"
require_c_fragment "$hosted_config_report_c" 'silt_host_arg_base' \
  "hosted-config-report did not read argument text boundaries"
require_c_fragment "$hosted_config_report_c" 'silt_host_file_read_base' \
  "hosted-config-report did not call the hosted file-read boundary"
require_c_fragment "$hosted_config_report_c" 'silt_host_file_read_len' \
  "hosted-config-report did not retain hosted file-read length evidence"
require_c_fragment "$hosted_config_report_c" 'silt_host_file_read_ok' \
  "hosted-config-report did not observe hosted file-read status"
require_c_fragment "$hosted_config_report_c" 'silt_layout_HostReadFileResult' \
  "hosted-config-report did not use the hosted file-read result layout"
require_c_fragment "$hosted_config_report_c" 'silt_host_file_write_bytes' \
  "hosted-config-report did not call the hosted file-write boundary"
require_c_fragment "$hosted_config_report_c" 'silt_host_put_byte(byte_' \
  "hosted-config-report did not write formatted output to stdout"
require_c_fragment "$hosted_config_report_c" 'silt_host_put_error_byte(byte_' \
  "hosted-config-report did not write diagnostics to stderr"
require_c_fragment "$hosted_config_report_c" 'silt_layout_TextSplitFirst' \
  "hosted-config-report did not retain text split result evidence"
require_c_fragment "$hosted_config_report_c" '== ((uint8_t)58u)' \
  "hosted-config-report did not retain colon split evidence"
require_c_fragment "$hosted_config_report_c" 'silt_layout_AsciiTrimState' \
  "hosted-config-report did not retain ASCII trim state evidence"
require_c_fragment "$hosted_config_report_c" '9ULL <=' \
  "hosted-config-report did not retain ASCII whitespace lower-bound evidence"
require_c_fragment "$hosted_config_report_c" '== ((uint8_t)32u)' \
  "hosted-config-report did not retain ASCII space trim evidence"
require_c_fragment "$hosted_config_report_c" 'silt_static_hosted_config_report_key_bytes' \
  "hosted-config-report did not retain static config key evidence"
require_c_fragment "$hosted_config_report_c" '* 10ULL) + (((uint64_t)byte_' \
  "hosted-config-report did not retain decimal parse accumulation evidence"
require_c_fragment "$hosted_config_report_c" '% 10ULL' \
  "hosted-config-report did not retain decimal format remainder evidence"
require_c_fragment "$hosted_config_report_c" '/ 10ULL' \
  "hosted-config-report did not retain decimal format division evidence"
require_c_fragment "$hosted_config_report_c" 'silt_cell_hosted_config_report_file_buffer' \
  "hosted-config-report did not retain its file-output formatting buffer"
require_c_fragment "$hosted_config_report_c" 'silt_cell_hosted_config_report_stdout_buffer' \
  "hosted-config-report did not retain its stdout formatting buffer"

"$silt_bin" build hosted-config-report >/dev/null
tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT
in_file="$tmp_dir/input.txt"
config_file="$tmp_dir/config.txt"
out_file="$tmp_dir/out.txt"
printf 'SILT_APP' >"$in_file"
printf ' expected : 8\n' >"$config_file"

run_case ok "$silt_bin" run hosted-config-report -- "$in_file" "$config_file" "$out_file"
expect_status success 0
expect_stdout_exact success "8"
expect_stderr_exact success ""
expect_file_exact success "$out_file" "8"

empty_file="$tmp_dir/empty.txt"
empty_config="$tmp_dir/empty-config.txt"
empty_out="$tmp_dir/empty-out.txt"
: >"$empty_file"
printf 'expected: 0\n' >"$empty_config"
run_case empty "$silt_bin" run hosted-config-report -- "$empty_file" "$empty_config" "$empty_out"
expect_status empty-file 0
expect_stdout_exact empty-file "0"
expect_stderr_exact empty-file ""
expect_file_exact empty-file "$empty_out" "0"

mismatch_config="$tmp_dir/mismatch-config.txt"
mismatch_out="$tmp_dir/mismatch.txt"
printf 'expected: 9\n' >"$mismatch_config"
run_case mismatch "$silt_bin" run hosted-config-report -- "$in_file" "$mismatch_config" "$mismatch_out"
expect_status mismatch 5
expect_stdout_exact mismatch "8"
expect_stderr_exact mismatch $'error: length mismatch\n'
expect_file_exact mismatch "$mismatch_out" "8"

invalid_expected_config="$tmp_dir/invalid-expected-config.txt"
invalid_expected_out="$tmp_dir/invalid-expected.txt"
printf 'expected: nope\n' >"$invalid_expected_config"
run_case invalid_expected "$silt_bin" run hosted-config-report -- "$in_file" "$invalid_expected_config" "$invalid_expected_out"
expect_status "invalid expected length" 4
expect_stdout_exact invalid-expected ""
expect_stderr_exact invalid-expected $'error: invalid expected length\n'
expect_file_absent "invalid expected length" "$invalid_expected_out"

missing_colon_config="$tmp_dir/missing-colon-config.txt"
missing_colon_out="$tmp_dir/missing-colon.txt"
printf 'expected 8\n' >"$missing_colon_config"
run_case missing_colon "$silt_bin" run hosted-config-report -- "$in_file" "$missing_colon_config" "$missing_colon_out"
expect_status "missing-colon config" 8
expect_stdout_exact missing-colon ""
expect_stderr_exact missing-colon $'error: invalid config\n'
expect_file_absent "invalid config" "$missing_colon_out"

wrong_key_config="$tmp_dir/wrong-key-config.txt"
wrong_key_out="$tmp_dir/wrong-key.txt"
printf 'actual: 8\n' >"$wrong_key_config"
run_case wrong_key "$silt_bin" run hosted-config-report -- "$in_file" "$wrong_key_config" "$wrong_key_out"
expect_status "wrong-key config" 9
expect_stdout_exact wrong-key ""
expect_stderr_exact wrong-key $'error: invalid config key\n'
expect_file_absent "invalid config key" "$wrong_key_out"

run_case missing "$silt_bin" run hosted-config-report
expect_status "without args" 2
expect_stdout_exact missing-args ""
expect_stderr_exact missing-args $'usage: hosted-config-report INPUT CONFIG OUTPUT\n'

extra_out="$tmp_dir/extra.txt"
run_case extra "$silt_bin" run hosted-config-report -- "$in_file" "$config_file" "$extra_out" ignored
expect_status "extra args" 2
expect_stdout_exact extra-args ""
expect_stderr_exact extra-args $'usage: hosted-config-report INPUT CONFIG OUTPUT\n'
expect_file_absent "extra args" "$extra_out"

input_read_failed_out="$tmp_dir/input-read-failed.txt"
run_case input_read_failed "$silt_bin" run hosted-config-report -- "$tmp_dir/missing-input.txt" "$config_file" "$input_read_failed_out"
expect_status "missing input" 6
expect_stdout_exact input-read-failure ""
expect_stderr_exact input-read-failure $'error: input read failed\n'
expect_file_absent "input read failure" "$input_read_failed_out"

config_read_failed_out="$tmp_dir/config-read-failed.txt"
run_case config_read_failed "$silt_bin" run hosted-config-report -- "$in_file" "$tmp_dir/missing-config.txt" "$config_read_failed_out"
expect_status "missing config" 7
expect_stdout_exact config-read-failure ""
expect_stderr_exact config-read-failure $'error: config read failed\n'
expect_file_absent "config read failure" "$config_read_failed_out"

run_case write_failed "$silt_bin" run hosted-config-report -- "$in_file" "$config_file" "$tmp_dir/nope/out.txt"
expect_status "write failure" 3
expect_stdout_exact write-failure ""
expect_stderr_exact write-failure $'error: write failed\n'

git diff --check
