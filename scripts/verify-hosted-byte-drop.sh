#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$script_dir/lib/verify-hosted-app.sh"

hosted_case_app=hosted-byte-drop
hosted_verify_setup

hosted_byte_drop_sources=(
  stdlib/core.silt
  stdlib/nat.silt
  stdlib/bytes.silt
  stdlib/text.silt
  stdlib/hosted.silt
  examples/hosted-byte-drop.silt
)

require_file_contains examples/hosted-byte-drop.silt 'host-read-stdin-result' \
  "hosted-byte-drop stopped using the hosted stdin result layout"
require_file_contains examples/hosted-byte-drop.silt 'hosted-byte-drop-loop' \
  "hosted-byte-drop stopped using its explicit byte loop"
require_file_contains examples/hosted-byte-drop.silt 'u8-eq byte needle' \
  "hosted-byte-drop stopped comparing loaded bytes against the argument byte"
require_file_contains examples/hosted-byte-drop.silt 'host-write-byte' \
  "hosted-byte-drop stopped writing kept bytes to stdout"
require_file_contains examples/hosted-byte-drop.silt 'host-status-with-error-text' \
  "hosted-byte-drop stopped using hosted status diagnostics"
"$silt_bin" check "${hosted_byte_drop_sources[@]}" >/dev/null

hosted_byte_drop_c="$("$silt_bin" emit-c-bundle "${hosted_byte_drop_sources[@]}" -- hosted-byte-drop-main)"
require_c_fragment "$hosted_byte_drop_c" 'silt_host_arg_count' \
  "hosted-byte-drop did not check process argument count"
require_c_fragment "$hosted_byte_drop_c" 'silt_host_arg_base' \
  "hosted-byte-drop did not read the byte argument base"
require_c_fragment "$hosted_byte_drop_c" 'silt_host_arg_len' \
  "hosted-byte-drop did not read the byte argument length"
require_c_fragment "$hosted_byte_drop_c" 'silt_host_stdin_read_base' \
  "hosted-byte-drop did not call the hosted stdin-read boundary"
require_c_fragment "$hosted_byte_drop_c" 'silt_host_stdin_read_ok' \
  "hosted-byte-drop did not observe hosted stdin-read status"
require_c_fragment "$hosted_byte_drop_c" 'silt_layout_HostReadStdinResult' \
  "hosted-byte-drop did not use the hosted stdin result layout"
require_c_fragment "$hosted_byte_drop_c" 'for (uint64_t index_' \
  "hosted-byte-drop did not lower the byte transform through a loop"
require_c_fragment "$hosted_byte_drop_c" '== needle_' \
  "hosted-byte-drop did not compare loaded bytes against the byte argument"
require_c_fragment "$hosted_byte_drop_c" 'silt_host_put_byte(byte_' \
  "hosted-byte-drop did not write kept bytes to stdout"
require_c_fragment "$hosted_byte_drop_c" 'silt_host_put_error_byte(byte_' \
  "hosted-byte-drop did not write diagnostics to stderr"

"$silt_bin" build hosted-byte-drop >/dev/null
tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

run_case drop-x bash -c 'printf "axbxxc\n" | "$1" run hosted-byte-drop -- x' _ "$silt_bin"
expect_status drop-x 0
expect_stdout_exact drop-x $'abc\n'
expect_stderr_exact drop-x ""

run_case binary bash -c 'printf "a\0xbx\n" | "$1" run hosted-byte-drop -- x' _ "$silt_bin"
expect_status binary 0
if ! printf 'a\0b\n' | cmp -s - "$case_stdout"; then
  fail_verify "unexpected hosted-byte-drop binary stdout"
fi
expect_stderr_exact binary ""

run_case empty bash -c 'printf "" | "$1" run hosted-byte-drop -- x' _ "$silt_bin"
expect_status empty 0
expect_stdout_exact empty ""
expect_stderr_exact empty ""

run_case missing bash -c 'printf "ignored\n" | "$1" run hosted-byte-drop' _ "$silt_bin"
expect_status missing-args 2
expect_stdout_exact missing-args ""
expect_stderr_exact missing-args $'usage: hosted-byte-drop BYTE < INPUT\n'

run_case extra bash -c 'printf "ignored\n" | "$1" run hosted-byte-drop -- x ignored' _ "$silt_bin"
expect_status extra-args 2
expect_stdout_exact extra-args ""
expect_stderr_exact extra-args $'usage: hosted-byte-drop BYTE < INPUT\n'

run_case empty-byte bash -c 'printf "ignored\n" | "$1" run hosted-byte-drop -- ""' _ "$silt_bin"
expect_status empty-byte 4
expect_stdout_exact empty-byte ""
expect_stderr_exact empty-byte $'error: invalid byte\n'

run_case wide-byte bash -c 'printf "ignored\n" | "$1" run hosted-byte-drop -- xy' _ "$silt_bin"
expect_status wide-byte 4
expect_stdout_exact wide-byte ""
expect_stderr_exact wide-byte $'error: invalid byte\n'

git diff --check
