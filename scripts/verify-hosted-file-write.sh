#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$script_dir/lib/verify-hosted-app.sh"

hosted_case_app=hosted-write-file
hosted_verify_setup

hosted_file_sources=(
  stdlib/core.silt
  stdlib/nat.silt
  stdlib/bytes.silt
  stdlib/text.silt
  stdlib/hosted.silt
  examples/hosted-write-file.silt
)

"$silt_bin" check "${hosted_file_sources[@]}" >/dev/null

hosted_file_c="$("$silt_bin" emit-c-bundle "${hosted_file_sources[@]}" -- hosted-write-file-main)"
require_c_fragment "$hosted_file_c" 'silt_host_file_write_bytes' \
  "hosted-write-file did not call the hosted file-write boundary"

"$silt_bin" build hosted-write-file >/dev/null
tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT
out_file="$tmp_dir/silt-hosted-file.txt"

run_case ok "$silt_bin" run hosted-write-file -- "$out_file"
expect_status success 0
expect_stdout_exact success ""
expect_stderr_exact success ""
expect_file_exact success "$out_file" $'SILT_FILE\n'

run_case missing "$silt_bin" run hosted-write-file
expect_status "without argv[1]" 3
expect_stdout_exact "without argv[1]" ""
expect_stderr_exact "without argv[1]" ""

git diff --check
