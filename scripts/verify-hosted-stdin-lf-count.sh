#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$script_dir/lib/verify-hosted-app.sh"

hosted_case_app=hosted-stdin-lf-count
hosted_verify_setup

hosted_stdin_lf_count_sources=(
  stdlib/core.silt
  stdlib/nat.silt
  stdlib/bytes.silt
  stdlib/text.silt
  stdlib/ascii.silt
  stdlib/ascii-decimal.silt
  stdlib/hosted.silt
  stdlib/hosted-decimal.silt
  examples/hosted-stdin-lf-count.silt
)

require_file_contains examples/hosted-stdin-lf-count.silt 'host-read-stdin-result' \
  "hosted-stdin-lf-count stopped using the hosted stdin result layout"
require_file_contains examples/hosted-stdin-lf-count.silt 'text-count-lf' \
  "hosted-stdin-lf-count stopped using the text LF counter"
require_file_contains examples/hosted-stdin-lf-count.silt 'host-write-u64-decimal' \
  "hosted-stdin-lf-count stopped using decimal stdout output"
require_file_contains examples/hosted-stdin-lf-count.silt 'host-status-with-error-text' \
  "hosted-stdin-lf-count stopped using hosted status diagnostics"
"$silt_bin" check "${hosted_stdin_lf_count_sources[@]}" >/dev/null

hosted_stdin_lf_count_c="$("$silt_bin" emit-c-bundle "${hosted_stdin_lf_count_sources[@]}" -- hosted-stdin-lf-count-main)"
require_c_fragment "$hosted_stdin_lf_count_c" 'silt_host_arg_count' \
  "hosted-stdin-lf-count did not check process argument count"
require_c_fragment "$hosted_stdin_lf_count_c" 'silt_host_stdin_read_base' \
  "hosted-stdin-lf-count did not call the hosted stdin-read boundary"
require_c_fragment "$hosted_stdin_lf_count_c" 'silt_host_stdin_read_len' \
  "hosted-stdin-lf-count did not observe hosted stdin-read length"
require_c_fragment "$hosted_stdin_lf_count_c" 'silt_host_stdin_read_ok' \
  "hosted-stdin-lf-count did not observe hosted stdin-read status"
require_c_fragment "$hosted_stdin_lf_count_c" 'silt_layout_HostReadStdinResult' \
  "hosted-stdin-lf-count did not use the hosted stdin result layout"
require_c_fragment "$hosted_stdin_lf_count_c" 'for (uint64_t index_' \
  "hosted-stdin-lf-count did not lower the LF count through a length-driven loop"
require_c_fragment "$hosted_stdin_lf_count_c" '(*((uint8_t*)' \
  "hosted-stdin-lf-count did not load bytes through explicit byte pointers"
require_c_fragment "$hosted_stdin_lf_count_c" '== ((uint8_t)10u)' \
  "hosted-stdin-lf-count did not compare loaded bytes against LF"
require_c_fragment "$hosted_stdin_lf_count_c" 'silt_host_put_byte(byte_' \
  "hosted-stdin-lf-count did not write formatted output to stdout"
require_c_fragment "$hosted_stdin_lf_count_c" 'silt_host_put_error_byte(byte_' \
  "hosted-stdin-lf-count did not write diagnostics to stderr"
require_c_fragment "$hosted_stdin_lf_count_c" '% 10ULL' \
  "hosted-stdin-lf-count did not retain decimal format remainder evidence"
require_c_fragment "$hosted_stdin_lf_count_c" '/ 10ULL' \
  "hosted-stdin-lf-count did not retain decimal format division evidence"
require_c_fragment "$hosted_stdin_lf_count_c" 'silt_cell_hosted_stdin_lf_count_stdout_buffer' \
  "hosted-stdin-lf-count did not retain its stdout formatting buffer"

"$silt_bin" build hosted-stdin-lf-count >/dev/null
tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

run_case lf bash -c 'printf "alpha\nbeta\ngamma\n" | "$1" run hosted-stdin-lf-count' _ "$silt_bin"
expect_status success 0
expect_stdout_exact lf "3"
expect_stderr_exact lf ""

run_case binary bash -c 'printf "alpha\0beta\nSILT\n" | "$1" run hosted-stdin-lf-count' _ "$silt_bin"
expect_status binary 0
expect_stdout_exact binary "2"
expect_stderr_exact binary ""

run_case empty bash -c 'printf "" | "$1" run hosted-stdin-lf-count' _ "$silt_bin"
expect_status empty 0
expect_stdout_exact empty "0"
expect_stderr_exact empty ""

run_case extra bash -c 'printf "ignored\n" | "$1" run hosted-stdin-lf-count -- ignored' _ "$silt_bin"
expect_status "extra args" 2
expect_stdout_exact extra-args ""
expect_stderr_exact extra-args $'usage: hosted-stdin-lf-count < INPUT\n'

git diff --check
