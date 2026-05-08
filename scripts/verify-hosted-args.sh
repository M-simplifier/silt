#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

if [ "${SILT_SKIP_CABAL_TEST:-0}" != "1" ]; then
  cabal test all
fi
cabal build exe:silt
silt_bin="$(cabal list-bin exe:silt)"

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
if ! grep -q 'silt_host_arg_base' <<<"$hosted_echo_c"; then
  echo "hosted-echo did not call the hosted argument base boundary" >&2
  exit 1
fi
if ! grep -q 'silt_host_arg_len' <<<"$hosted_echo_c"; then
  echo "hosted-echo did not call the hosted argument length boundary" >&2
  exit 1
fi
if ! grep -q 'silt_host_put_byte(byte_' <<<"$hosted_echo_c"; then
  echo "hosted-echo did not write argument text through hosted byte output" >&2
  exit 1
fi

"$silt_bin" build hosted-echo >/dev/null
echo_output="$("$silt_bin" run hosted-echo -- SILT_ARG)"
if [ "$echo_output" != "SILT_ARG" ]; then
  echo "unexpected hosted-echo output: $echo_output" >&2
  exit 1
fi

empty_output="$("$silt_bin" run hosted-echo)"
if [ "$empty_output" != "" ]; then
  echo "unexpected hosted-echo output without argv[1]: $empty_output" >&2
  exit 1
fi

git diff --check
