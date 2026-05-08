#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

if [ "${SILT_SKIP_CABAL_TEST:-0}" != "1" ]; then
  cabal test all
fi
cabal build exe:silt
silt_bin="$(cabal list-bin exe:silt)"

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
if ! grep -q 'silt_host_env_present' <<<"$hosted_env_ready_c"; then
  echo "hosted-env-ready did not call the hosted env presence boundary" >&2
  exit 1
fi

hosted_env_c="$("$silt_bin" emit-c-bundle "${hosted_env_sources[@]}" -- hosted-env-main)"
if ! grep -q 'silt_host_env_base' <<<"$hosted_env_c"; then
  echo "hosted-env did not call the hosted env base boundary" >&2
  exit 1
fi
if ! grep -q 'silt_host_env_len' <<<"$hosted_env_c"; then
  echo "hosted-env did not call the hosted env length boundary" >&2
  exit 1
fi
if ! grep -q 'silt_host_put_byte(byte_' <<<"$hosted_env_c"; then
  echo "hosted-env did not write environment text through hosted byte output" >&2
  exit 1
fi

"$silt_bin" build hosted-env >/dev/null
env_output="$(SILT_HOSTED_ENV=SILT_ENV_VALUE "$silt_bin" run hosted-env)"
if [ "$env_output" != "SILT_ENV_VALUE" ]; then
  echo "unexpected hosted-env output: $env_output" >&2
  exit 1
fi

missing_output="$(env -u SILT_HOSTED_ENV "$silt_bin" run hosted-env)"
if [ "$missing_output" != "" ]; then
  echo "unexpected hosted-env output without SILT_HOSTED_ENV: $missing_output" >&2
  exit 1
fi

git diff --check
