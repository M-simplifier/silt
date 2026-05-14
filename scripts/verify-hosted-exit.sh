#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$script_dir/lib/verify-hosted-app.sh"

hosted_case_app=hosted-exit
hosted_verify_setup

hosted_exit_sources=(
  stdlib/core.silt
  stdlib/nat.silt
  stdlib/bytes.silt
  stdlib/text.silt
  stdlib/hosted.silt
  examples/hosted-exit.silt
)

"$silt_bin" check "${hosted_exit_sources[@]}" >/dev/null

hosted_exit_c="$("$silt_bin" emit-c-bundle "${hosted_exit_sources[@]}" -- hosted-exit-main)"
require_c_fragment "$hosted_exit_c" 'silt_host_arg_count' \
  "hosted-exit did not call the hosted argument count boundary"

"$silt_bin" build hosted-exit >/dev/null
tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

run_case ok "$silt_bin" run hosted-exit -- ok
expect_status success 0
expect_stdout_exact success ""
expect_stderr_exact success ""

run_case missing "$silt_bin" run hosted-exit
expect_status "without argv[1]" 2
expect_stdout_exact "without argv[1]" ""
expect_stderr_exact "without argv[1]" ""

git diff --check
