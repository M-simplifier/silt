#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

if [ "${SILT_SKIP_CABAL_TEST:-0}" != "1" ]; then
  cabal test all
fi
cabal build exe:silt
silt_bin="$(cabal list-bin exe:silt)"

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
if ! grep -q 'silt_host_arg_count' <<<"$hosted_exit_c"; then
  echo "hosted-exit did not call the hosted argument count boundary" >&2
  exit 1
fi

"$silt_bin" build hosted-exit >/dev/null
ok_output="$("$silt_bin" run hosted-exit -- ok)"
if [ "$ok_output" != "" ]; then
  echo "unexpected hosted-exit success output: $ok_output" >&2
  exit 1
fi

set +e
missing_output="$("$silt_bin" run hosted-exit)"
missing_status=$?
set -e
if [ "$missing_status" -ne 2 ]; then
  echo "expected hosted-exit without argv[1] to exit 2, got $missing_status" >&2
  exit 1
fi
if [ "$missing_output" != "" ]; then
  echo "unexpected hosted-exit failure output: $missing_output" >&2
  exit 1
fi

git diff --check
