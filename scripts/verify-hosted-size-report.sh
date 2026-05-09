#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

if [ "${SILT_SKIP_CABAL_TEST:-0}" != "1" ]; then
  cabal test all
fi
cabal build exe:silt
silt_bin="$(cabal list-bin exe:silt)"

hosted_size_report_sources=(
  stdlib/core.silt
  stdlib/nat.silt
  stdlib/bytes.silt
  stdlib/text.silt
  stdlib/ascii.silt
  stdlib/ascii-decimal.silt
  stdlib/hosted.silt
  examples/hosted-size-report.silt
)

"$silt_bin" check "${hosted_size_report_sources[@]}" >/dev/null

hosted_size_report_c="$("$silt_bin" emit-c-bundle "${hosted_size_report_sources[@]}" -- hosted-size-report-main)"
if ! grep -Fq 'silt_host_arg_count' <<<"$hosted_size_report_c"; then
  echo "hosted-size-report did not check process argument count" >&2
  exit 1
fi
if ! grep -Fq 'silt_host_arg_base' <<<"$hosted_size_report_c"; then
  echo "hosted-size-report did not read argument text boundaries" >&2
  exit 1
fi
if ! grep -Fq 'silt_host_file_read_base' <<<"$hosted_size_report_c"; then
  echo "hosted-size-report did not call the hosted file-read boundary" >&2
  exit 1
fi
if ! grep -Fq 'silt_host_file_read_ok' <<<"$hosted_size_report_c"; then
  echo "hosted-size-report did not observe hosted file-read status" >&2
  exit 1
fi
if ! grep -Fq 'silt_host_file_write_bytes' <<<"$hosted_size_report_c"; then
  echo "hosted-size-report did not call the hosted file-write boundary" >&2
  exit 1
fi
if ! grep -Fq 'silt_host_put_byte(byte_' <<<"$hosted_size_report_c"; then
  echo "hosted-size-report did not write formatted output to stdout" >&2
  exit 1
fi
if ! grep -Fq '* 10ULL) + (((uint64_t)byte_' <<<"$hosted_size_report_c"; then
  echo "hosted-size-report did not retain decimal parse accumulation evidence" >&2
  exit 1
fi
if ! grep -Fq '% 10ULL' <<<"$hosted_size_report_c"; then
  echo "hosted-size-report did not retain decimal format remainder evidence" >&2
  exit 1
fi
if ! grep -Fq '/ 10ULL' <<<"$hosted_size_report_c"; then
  echo "hosted-size-report did not retain decimal format division evidence" >&2
  exit 1
fi
if ! grep -Fq 'silt_cell_hosted_size_report_file_buffer' <<<"$hosted_size_report_c"; then
  echo "hosted-size-report did not retain its file-output formatting buffer" >&2
  exit 1
fi
if ! grep -Fq 'silt_cell_hosted_size_report_stdout_buffer' <<<"$hosted_size_report_c"; then
  echo "hosted-size-report did not retain its stdout formatting buffer" >&2
  exit 1
fi

"$silt_bin" build hosted-size-report >/dev/null
tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT
in_file="$tmp_dir/input.txt"
out_file="$tmp_dir/out.txt"
printf 'SILT_APP' > "$in_file"

ok_output="$("$silt_bin" run hosted-size-report -- "$in_file" 8 "$out_file")"
if [ "$ok_output" != "8" ]; then
  echo "unexpected hosted-size-report success stdout: $ok_output" >&2
  exit 1
fi
if [ "$(<"$out_file")" != "8" ]; then
  echo "hosted-size-report wrote unexpected success output file" >&2
  exit 1
fi

empty_file="$tmp_dir/empty.txt"
empty_out="$tmp_dir/empty-out.txt"
: > "$empty_file"
empty_output="$("$silt_bin" run hosted-size-report -- "$empty_file" 0 "$empty_out")"
if [ "$empty_output" != "0" ]; then
  echo "unexpected hosted-size-report empty-file stdout: $empty_output" >&2
  exit 1
fi
if [ "$(<"$empty_out")" != "0" ]; then
  echo "hosted-size-report wrote unexpected empty-file output file" >&2
  exit 1
fi

mismatch_out="$tmp_dir/mismatch.txt"
set +e
mismatch_output="$("$silt_bin" run hosted-size-report -- "$in_file" 9 "$mismatch_out")"
mismatch_status=$?
set -e
if [ "$mismatch_status" -ne 5 ]; then
  echo "expected hosted-size-report mismatch to exit 5, got $mismatch_status" >&2
  exit 1
fi
if [ "$mismatch_output" != "8" ]; then
  echo "unexpected hosted-size-report mismatch stdout: $mismatch_output" >&2
  exit 1
fi
if [ "$(<"$mismatch_out")" != "8" ]; then
  echo "hosted-size-report wrote unexpected mismatch output file" >&2
  exit 1
fi

invalid_out="$tmp_dir/invalid.txt"
set +e
invalid_output="$("$silt_bin" run hosted-size-report -- "$in_file" nope "$invalid_out")"
invalid_status=$?
set -e
if [ "$invalid_status" -ne 4 ]; then
  echo "expected hosted-size-report invalid expected length to exit 4, got $invalid_status" >&2
  exit 1
fi
if [ "$invalid_output" != "" ]; then
  echo "unexpected hosted-size-report invalid expected stdout: $invalid_output" >&2
  exit 1
fi
if [ -e "$invalid_out" ]; then
  echo "hosted-size-report wrote a file after invalid expected length" >&2
  exit 1
fi

set +e
missing_output="$("$silt_bin" run hosted-size-report)"
missing_status=$?
set -e
if [ "$missing_status" -ne 2 ]; then
  echo "expected hosted-size-report without args to exit 2, got $missing_status" >&2
  exit 1
fi
if [ "$missing_output" != "" ]; then
  echo "unexpected hosted-size-report missing-args stdout: $missing_output" >&2
  exit 1
fi

extra_out="$tmp_dir/extra.txt"
set +e
extra_output="$("$silt_bin" run hosted-size-report -- "$in_file" 8 "$extra_out" ignored)"
extra_status=$?
set -e
if [ "$extra_status" -ne 2 ]; then
  echo "expected hosted-size-report extra args to exit 2, got $extra_status" >&2
  exit 1
fi
if [ "$extra_output" != "" ]; then
  echo "unexpected hosted-size-report extra-args stdout: $extra_output" >&2
  exit 1
fi
if [ -e "$extra_out" ]; then
  echo "hosted-size-report wrote a file after extra args" >&2
  exit 1
fi

read_failed_out="$tmp_dir/read-failed.txt"
set +e
read_failed_output="$("$silt_bin" run hosted-size-report -- "$tmp_dir/missing-input.txt" 0 "$read_failed_out")"
read_failed_status=$?
set -e
if [ "$read_failed_status" -ne 6 ]; then
  echo "expected hosted-size-report missing input to exit 6, got $read_failed_status" >&2
  exit 1
fi
if [ "$read_failed_output" != "" ]; then
  echo "unexpected hosted-size-report read-failure stdout: $read_failed_output" >&2
  exit 1
fi
if [ -e "$read_failed_out" ]; then
  echo "hosted-size-report wrote a file after read failure" >&2
  exit 1
fi

set +e
write_failed_output="$("$silt_bin" run hosted-size-report -- "$in_file" 8 "$tmp_dir/nope/out.txt")"
write_failed_status=$?
set -e
if [ "$write_failed_status" -ne 3 ]; then
  echo "expected hosted-size-report write failure to exit 3, got $write_failed_status" >&2
  exit 1
fi
if [ "$write_failed_output" != "" ]; then
  echo "unexpected hosted-size-report write-failure stdout: $write_failed_output" >&2
  exit 1
fi

git diff --check
