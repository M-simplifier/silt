#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

if [ "${SILT_SKIP_CABAL_TEST:-0}" != "1" ]; then
  cabal test all
fi
cabal build exe:silt
silt_bin="$(cabal list-bin exe:silt)"

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
if ! grep -q 'silt_host_file_write_bytes' <<<"$hosted_file_c"; then
  echo "hosted-write-file did not call the hosted file-write boundary" >&2
  exit 1
fi

"$silt_bin" build hosted-write-file >/dev/null
tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT
out_file="$tmp_dir/silt-hosted-file.txt"
expected_file="$tmp_dir/expected.txt"
printf 'SILT_FILE\n' > "$expected_file"

ok_output="$("$silt_bin" run hosted-write-file -- "$out_file")"
if [ "$ok_output" != "" ]; then
  echo "unexpected hosted-write-file success output: $ok_output" >&2
  exit 1
fi
if ! cmp -s "$expected_file" "$out_file"; then
  echo "hosted-write-file wrote unexpected file content" >&2
  exit 1
fi

set +e
missing_output="$("$silt_bin" run hosted-write-file)"
missing_status=$?
set -e
if [ "$missing_status" -ne 3 ]; then
  echo "expected hosted-write-file without argv[1] to exit 3, got $missing_status" >&2
  exit 1
fi
if [ "$missing_output" != "" ]; then
  echo "unexpected hosted-write-file failure output: $missing_output" >&2
  exit 1
fi

git diff --check
