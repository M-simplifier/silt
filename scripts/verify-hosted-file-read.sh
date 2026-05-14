#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$script_dir/lib/verify-hosted-app.sh"

hosted_case_app=hosted-cat
hosted_verify_setup

hosted_file_sources=(
  stdlib/core.silt
  stdlib/nat.silt
  stdlib/bytes.silt
  stdlib/text.silt
  stdlib/hosted.silt
  examples/hosted-cat.silt
)

"$silt_bin" check "${hosted_file_sources[@]}" >/dev/null

hosted_file_c="$("$silt_bin" emit-c-bundle "${hosted_file_sources[@]}" -- hosted-cat-main)"
require_c_fragment "$hosted_file_c" 'silt_host_file_read_base' \
  "hosted-cat did not call the hosted file-read base boundary"
require_c_fragment "$hosted_file_c" 'silt_host_file_read_len' \
  "hosted-cat did not call the hosted file-read length boundary"
require_c_fragment "$hosted_file_c" 'silt_host_put_byte(byte_' \
  "hosted-cat did not write file text through hosted byte output"

"$silt_bin" build hosted-cat >/dev/null
tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT
in_file="$tmp_dir/silt-hosted-file.txt"
printf 'SILT_READ' > "$in_file"

run_case read "$silt_bin" run hosted-cat -- "$in_file"
expect_status read 0
expect_stdout_exact read "SILT_READ"
expect_stderr_exact read ""

run_case missing "$silt_bin" run hosted-cat -- "$tmp_dir/missing.txt"
expect_status missing 0
expect_stdout_exact missing ""
expect_stderr_exact missing ""

git diff --check
