#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$script_dir/lib/verify-hosted-app.sh"

hosted_case_app=hosted-env
hosted_verify_setup

hosted_env_sources=(
  stdlib/core.silt
  stdlib/nat.silt
  stdlib/bytes.silt
  stdlib/text.silt
  stdlib/hosted.silt
  examples/hosted-env.silt
)

"$silt_bin" check "${hosted_env_sources[@]}" >/dev/null

hosted_env_ready_c="$("$silt_bin" emit-c-bundle "${hosted_env_sources[@]}" -- hosted-env-ready)"
require_c_fragment "$hosted_env_ready_c" 'silt_host_env_present' \
  "hosted-env-ready did not call the hosted env presence boundary"

hosted_env_c="$("$silt_bin" emit-c-bundle "${hosted_env_sources[@]}" -- hosted-env-main)"
require_c_fragment "$hosted_env_c" 'silt_host_env_base' \
  "hosted-env did not call the hosted env base boundary"
require_c_fragment "$hosted_env_c" 'silt_host_env_len' \
  "hosted-env did not call the hosted env length boundary"
require_c_fragment "$hosted_env_c" 'silt_host_put_byte(byte_' \
  "hosted-env did not write environment text through hosted byte output"

"$silt_bin" build hosted-env >/dev/null
tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

run_case present env SILT_HOSTED_ENV=SILT_ENV_VALUE "$silt_bin" run hosted-env
expect_status present 0
expect_stdout_exact present $'SILT_ENV_VALUE\n'
expect_stderr_exact present ""

run_case missing env -u SILT_HOSTED_ENV "$silt_bin" run hosted-env
expect_status missing 0
expect_stdout_exact missing $'\n'
expect_stderr_exact missing ""

git diff --check
