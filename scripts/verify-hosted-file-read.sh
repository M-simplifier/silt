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
  examples/hosted-cat.silt
)

"$silt_bin" check "${hosted_file_sources[@]}" >/dev/null

hosted_file_c="$("$silt_bin" emit-c-bundle "${hosted_file_sources[@]}" -- hosted-cat-main)"
if ! grep -q 'silt_host_file_read_base' <<<"$hosted_file_c"; then
  echo "hosted-cat did not call the hosted file-read base boundary" >&2
  exit 1
fi
if ! grep -q 'silt_host_file_read_len' <<<"$hosted_file_c"; then
  echo "hosted-cat did not call the hosted file-read length boundary" >&2
  exit 1
fi
if ! grep -q 'silt_host_put_byte(byte_' <<<"$hosted_file_c"; then
  echo "hosted-cat did not write file text through hosted byte output" >&2
  exit 1
fi

"$silt_bin" build hosted-cat >/dev/null
tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT
in_file="$tmp_dir/silt-hosted-file.txt"
printf 'SILT_READ' > "$in_file"

cat_output="$("$silt_bin" run hosted-cat -- "$in_file")"
if [ "$cat_output" != "SILT_READ" ]; then
  echo "unexpected hosted-cat output: $cat_output" >&2
  exit 1
fi

missing_output="$("$silt_bin" run hosted-cat -- "$tmp_dir/missing.txt")"
if [ "$missing_output" != "" ]; then
  echo "unexpected hosted-cat output for missing file: $missing_output" >&2
  exit 1
fi

git diff --check
