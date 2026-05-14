#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$script_dir/lib/verify-hosted-app.sh"

hosted_case_app=hosted-echo
hosted_verify_setup

hosted_arg_sources=(
  stdlib/core.silt
  stdlib/nat.silt
  stdlib/bytes.silt
  stdlib/text.silt
  stdlib/hosted.silt
  examples/hosted-echo.silt
)

"$silt_bin" check "${hosted_arg_sources[@]}" >/dev/null

hosted_echo_c="$("$silt_bin" emit-c-bundle "${hosted_arg_sources[@]}" -- hosted-echo-main)"
require_c_fragment "$hosted_echo_c" 'silt_host_arg_base' \
  "hosted-echo did not call the hosted argument base boundary"
require_c_fragment "$hosted_echo_c" 'silt_host_arg_len' \
  "hosted-echo did not call the hosted argument length boundary"
require_c_fragment "$hosted_echo_c" 'silt_host_put_byte(byte_' \
  "hosted-echo did not write argument text through hosted byte output"

"$silt_bin" build hosted-echo >/dev/null
tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

run_case arg "$silt_bin" run hosted-echo -- SILT_ARG
expect_status "with argv[1]" 0
expect_stdout_exact "with argv[1]" $'SILT_ARG\n'
expect_stderr_exact "with argv[1]" ""

run_case empty "$silt_bin" run hosted-echo
expect_status "without argv[1]" 0
expect_stdout_exact "without argv[1]" $'\n'
expect_stderr_exact "without argv[1]" ""

git diff --check
