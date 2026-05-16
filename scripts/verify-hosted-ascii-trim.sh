#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$script_dir/lib/verify-hosted-app.sh"

hosted_case_app=hosted-ascii-trim
hosted_verify_setup

hosted_ascii_trim_sources=(
  stdlib/core.silt
  stdlib/nat.silt
  stdlib/bytes.silt
  stdlib/text.silt
  stdlib/ascii.silt
  stdlib/ascii-slice.silt
  stdlib/hosted.silt
  examples/hosted-ascii-trim.silt
)

require_file_contains examples/hosted-ascii-trim.silt 'text-trim-ascii-whitespace HostIO body' \
  "hosted-ascii-trim stopped using the ASCII whitespace trim helper"
require_file_contains examples/hosted-ascii-trim.silt 'host-read-file-result' \
  "hosted-ascii-trim stopped using the hosted file-read result layout"
require_file_contains examples/hosted-ascii-trim.silt 'host-write-file output-path' \
  "hosted-ascii-trim stopped using the hosted file-write boundary"
require_file_contains examples/hosted-ascii-trim.silt 'host-write-text' \
  "hosted-ascii-trim stopped writing trimmed bytes to stdout"
require_file_contains examples/hosted-ascii-trim.silt 'host-status-with-error-text' \
  "hosted-ascii-trim stopped using hosted status diagnostics"
"$silt_bin" check "${hosted_ascii_trim_sources[@]}" >/dev/null

hosted_ascii_trim_c="$("$silt_bin" emit-c-bundle "${hosted_ascii_trim_sources[@]}" -- hosted-ascii-trim-main)"
require_c_fragment "$hosted_ascii_trim_c" 'silt_host_arg_count' \
  "hosted-ascii-trim did not check process argument count"
require_c_fragment "$hosted_ascii_trim_c" 'silt_host_arg_base' \
  "hosted-ascii-trim did not read argument text boundaries"
require_c_fragment "$hosted_ascii_trim_c" 'silt_host_file_read_base' \
  "hosted-ascii-trim did not call the hosted file-read boundary"
require_c_fragment "$hosted_ascii_trim_c" 'silt_host_file_read_ok' \
  "hosted-ascii-trim did not observe hosted file-read status"
require_c_fragment "$hosted_ascii_trim_c" 'silt_layout_HostReadFileResult' \
  "hosted-ascii-trim did not use the hosted file-read result layout"
require_c_fragment "$hosted_ascii_trim_c" 'silt_layout_AsciiTrimState' \
  "hosted-ascii-trim did not retain the ASCII trim state layout"
require_c_fragment "$hosted_ascii_trim_c" 'for (uint64_t index_' \
  "hosted-ascii-trim did not lower ASCII trim through a length-driven loop"
require_c_fragment "$hosted_ascii_trim_c" '9ULL <=' \
  "hosted-ascii-trim did not retain ASCII whitespace lower-bound evidence"
require_c_fragment "$hosted_ascii_trim_c" '13ULL' \
  "hosted-ascii-trim did not retain ASCII whitespace upper-bound evidence"
require_c_fragment "$hosted_ascii_trim_c" '== ((uint8_t)32u)' \
  "hosted-ascii-trim did not retain ASCII space evidence"
require_c_fragment "$hosted_ascii_trim_c" 'silt_host_file_write_bytes' \
  "hosted-ascii-trim did not call the hosted file-write boundary"
require_c_fragment "$hosted_ascii_trim_c" 'silt_host_put_byte(byte_' \
  "hosted-ascii-trim did not write trimmed bytes to stdout"
require_c_fragment "$hosted_ascii_trim_c" 'silt_host_put_error_byte(byte_' \
  "hosted-ascii-trim did not write diagnostics to stderr"

"$silt_bin" build hosted-ascii-trim >/dev/null
tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

trim_input="$tmp_dir/trim-input.txt"
trim_output="$tmp_dir/trim-output.txt"
printf ' \tSILT\n ' >"$trim_input"
run_case trim "$silt_bin" run hosted-ascii-trim -- "$trim_input" "$trim_output"
expect_status trim 0
expect_stdout_exact trim "SILT"
expect_stderr_exact trim ""
expect_file_exact trim "$trim_output" "SILT"

clean_input="$tmp_dir/clean-input.txt"
clean_output="$tmp_dir/clean-output.txt"
printf 'alpha' >"$clean_input"
run_case clean "$silt_bin" run hosted-ascii-trim -- "$clean_input" "$clean_output"
expect_status clean 0
expect_stdout_exact clean "alpha"
expect_stderr_exact clean ""
expect_file_exact clean "$clean_output" "alpha"

space_input="$tmp_dir/space-input.txt"
space_output="$tmp_dir/space-output.txt"
printf ' \t\n\r ' >"$space_input"
run_case all_space "$silt_bin" run hosted-ascii-trim -- "$space_input" "$space_output"
expect_status "all whitespace" 0
expect_stdout_exact "all whitespace" ""
expect_stderr_exact "all whitespace" ""
expect_file_exact "all whitespace" "$space_output" ""

interior_input="$tmp_dir/interior-input.txt"
interior_output="$tmp_dir/interior-output.txt"
printf ' alpha beta \n' >"$interior_input"
run_case interior "$silt_bin" run hosted-ascii-trim -- "$interior_input" "$interior_output"
expect_status interior 0
expect_stdout_exact interior "alpha beta"
expect_stderr_exact interior ""
expect_file_exact interior "$interior_output" "alpha beta"

non_ascii_input="$tmp_dir/non-ascii-input.txt"
non_ascii_output="$tmp_dir/non-ascii-output.txt"
non_ascii_expected="$(printf '\303\251')"
printf ' \303\251 ' >"$non_ascii_input"
run_case non_ascii "$silt_bin" run hosted-ascii-trim -- "$non_ascii_input" "$non_ascii_output"
expect_status non_ascii 0
expect_stdout_exact non_ascii "$non_ascii_expected"
expect_stderr_exact non_ascii ""
expect_file_exact non_ascii "$non_ascii_output" "$non_ascii_expected"

empty_input="$tmp_dir/empty-input.txt"
empty_output="$tmp_dir/empty-output.txt"
: >"$empty_input"
run_case empty "$silt_bin" run hosted-ascii-trim -- "$empty_input" "$empty_output"
expect_status empty 0
expect_stdout_exact empty ""
expect_stderr_exact empty ""
expect_file_exact empty "$empty_output" ""

run_case no_args "$silt_bin" run hosted-ascii-trim
expect_status "without args" 2
expect_stdout_exact "without args" ""
expect_stderr_exact "without args" $'usage: hosted-ascii-trim INPUT OUTPUT\n'

extra_output="$tmp_dir/extra-output.txt"
run_case extra "$silt_bin" run hosted-ascii-trim -- "$trim_input" "$extra_output" ignored
expect_status "extra args" 2
expect_stdout_exact "extra args" ""
expect_stderr_exact "extra args" $'usage: hosted-ascii-trim INPUT OUTPUT\n'
expect_file_absent "extra args" "$extra_output"

read_failed_output="$tmp_dir/read-failed-output.txt"
run_case read_failed "$silt_bin" run hosted-ascii-trim -- "$tmp_dir/missing-input.txt" "$read_failed_output"
expect_status "read failure" 6
expect_stdout_exact "read failure" ""
expect_stderr_exact "read failure" $'error: read failed\n'
expect_file_absent "read failure" "$read_failed_output"

run_case write_failed "$silt_bin" run hosted-ascii-trim -- "$trim_input" "$tmp_dir"
expect_status "write failure" 3
expect_stdout_exact "write failure" ""
expect_stderr_exact "write failure" $'error: write failed\n'

git diff --check
