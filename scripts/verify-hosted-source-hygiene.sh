#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$script_dir/lib/verify-hosted-app.sh"

hosted_case_app=hosted-source-hygiene
hosted_verify_setup

hosted_source_hygiene_sources=(
  stdlib/core.silt
  stdlib/nat.silt
  stdlib/bytes.silt
  stdlib/text.silt
  stdlib/hosted.silt
  examples/hosted-source-hygiene.silt
)

require_file_contains examples/hosted-source-hygiene.silt 'host-read-file-result' \
  "hosted-source-hygiene stopped using the hosted file-read result layout"
require_file_contains examples/hosted-source-hygiene.silt 'text-contains-byte HostIO body (u8 0)' \
  "hosted-source-hygiene stopped checking for NUL bytes"
require_file_contains examples/hosted-source-hygiene.silt 'text-contains-byte HostIO body (u8 13)' \
  "hosted-source-hygiene stopped checking for CR bytes"
require_file_contains examples/hosted-source-hygiene.silt 'host-status-with-error-text' \
  "hosted-source-hygiene stopped using hosted status diagnostics"
"$silt_bin" check "${hosted_source_hygiene_sources[@]}" >/dev/null

hosted_source_hygiene_c="$("$silt_bin" emit-c-bundle "${hosted_source_hygiene_sources[@]}" -- hosted-source-hygiene-main)"
require_c_fragment "$hosted_source_hygiene_c" 'silt_host_arg_count' \
  "hosted-source-hygiene did not check process argument count"
require_c_fragment "$hosted_source_hygiene_c" 'silt_host_arg_base' \
  "hosted-source-hygiene did not read argument text boundaries"
require_c_fragment "$hosted_source_hygiene_c" 'silt_host_file_read_base' \
  "hosted-source-hygiene did not call the hosted file-read boundary"
require_c_fragment "$hosted_source_hygiene_c" 'silt_host_file_read_ok' \
  "hosted-source-hygiene did not observe hosted file-read status"
require_c_fragment "$hosted_source_hygiene_c" 'silt_layout_HostReadFileResult' \
  "hosted-source-hygiene did not use the hosted file-read result layout"
require_c_fragment "$hosted_source_hygiene_c" 'for (uint64_t index_' \
  "hosted-source-hygiene did not lower byte checks through a loop"
require_c_fragment "$hosted_source_hygiene_c" '== ((uint8_t)0u)' \
  "hosted-source-hygiene did not compare file bytes against NUL"
require_c_fragment "$hosted_source_hygiene_c" '== ((uint8_t)13u)' \
  "hosted-source-hygiene did not compare file bytes against CR"
require_c_fragment "$hosted_source_hygiene_c" 'silt_static_hosted_source_hygiene_clean_bytes' \
  "hosted-source-hygiene did not retain its clean output text"
require_c_fragment "$hosted_source_hygiene_c" 'silt_static_hosted_source_hygiene_nul_bytes' \
  "hosted-source-hygiene did not retain its NUL output text"
require_c_fragment "$hosted_source_hygiene_c" 'silt_static_hosted_source_hygiene_cr_bytes' \
  "hosted-source-hygiene did not retain its CR output text"
require_c_fragment "$hosted_source_hygiene_c" 'silt_host_put_byte(byte_' \
  "hosted-source-hygiene did not write result text to stdout"
require_c_fragment "$hosted_source_hygiene_c" 'silt_host_put_error_byte(byte_' \
  "hosted-source-hygiene did not write diagnostics to stderr"

"$silt_bin" build hosted-source-hygiene >/dev/null
tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

clean_file="$tmp_dir/clean.silt"
nul_file="$tmp_dir/nul.silt"
cr_file="$tmp_dir/cr.silt"
both_file="$tmp_dir/both.silt"
empty_file="$tmp_dir/empty.silt"

cp examples/hosted-byte-drop.silt "$clean_file"
printf 'alpha\0beta\n' >"$nul_file"
printf 'alpha\rbeta\n' >"$cr_file"
printf 'alpha\0beta\r\n' >"$both_file"
: >"$empty_file"

run_case clean "$silt_bin" run hosted-source-hygiene -- "$clean_file"
expect_status clean 0
expect_stdout_exact clean $'clean\n'
expect_stderr_exact clean ""

run_case nul "$silt_bin" run hosted-source-hygiene -- "$nul_file"
expect_status nul 1
expect_stdout_exact nul $'nul\n'
expect_stderr_exact nul ""

run_case cr "$silt_bin" run hosted-source-hygiene -- "$cr_file"
expect_status cr 1
expect_stdout_exact cr $'cr\n'
expect_stderr_exact cr ""

run_case both "$silt_bin" run hosted-source-hygiene -- "$both_file"
expect_status both 1
expect_stdout_exact both $'nul\n'
expect_stderr_exact both ""

run_case empty "$silt_bin" run hosted-source-hygiene -- "$empty_file"
expect_status empty 0
expect_stdout_exact empty $'clean\n'
expect_stderr_exact empty ""

run_case no_args "$silt_bin" run hosted-source-hygiene
expect_status "without args" 2
expect_stdout_exact "without args" ""
expect_stderr_exact "without args" $'usage: hosted-source-hygiene INPUT\n'

run_case extra "$silt_bin" run hosted-source-hygiene -- "$clean_file" ignored
expect_status "extra args" 2
expect_stdout_exact "extra args" ""
expect_stderr_exact "extra args" $'usage: hosted-source-hygiene INPUT\n'

run_case read_failed "$silt_bin" run hosted-source-hygiene -- "$tmp_dir/missing.silt"
expect_status "read failure" 6
expect_stdout_exact "read failure" ""
expect_stderr_exact "read failure" $'error: read failed\n'

git diff --check
