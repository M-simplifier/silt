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
  stdlib/hosted-decimal.silt
  examples/hosted-size-report.silt
)

grep -Fq 'host-status-with-error-text' examples/hosted-size-report.silt
grep -Fq 'host-write-file-u64-decimal' examples/hosted-size-report.silt
grep -Fq 'host-write-u64-decimal' examples/hosted-size-report.silt
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
if ! grep -Fq 'silt_host_file_read_len' <<<"$hosted_size_report_c"; then
  echo "hosted-size-report did not retain hosted file-read length evidence" >&2
  exit 1
fi
if ! grep -Fq 'silt_host_file_read_ok' <<<"$hosted_size_report_c"; then
  echo "hosted-size-report did not observe hosted file-read status" >&2
  exit 1
fi
if ! grep -Fq 'silt_layout_HostReadFileResult' <<<"$hosted_size_report_c"; then
  echo "hosted-size-report did not use the hosted file-read result layout" >&2
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
if ! grep -Fq 'silt_host_put_error_byte(byte_' <<<"$hosted_size_report_c"; then
  echo "hosted-size-report did not write diagnostics to stderr" >&2
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

run_case() {
  local label="$1"
  shift
  case_stdout="$tmp_dir/$label.stdout"
  case_stderr="$tmp_dir/$label.stderr"
  set +e
  "$@" >"$case_stdout" 2>"$case_stderr"
  case_status=$?
  set -e
  case_output="$(<"$case_stdout")"
}

expect_stdout_exact() {
  local label="$1"
  local expected="$2"
  if ! printf '%s' "$expected" | cmp -s - "$case_stdout"; then
    echo "unexpected hosted-size-report $label stdout" >&2
    exit 1
  fi
}

expect_stderr_exact() {
  local label="$1"
  local expected="$2"
  if ! printf '%s' "$expected" | cmp -s - "$case_stderr"; then
    echo "unexpected hosted-size-report $label stderr" >&2
    exit 1
  fi
}

run_case ok "$silt_bin" run hosted-size-report -- "$in_file" 8 "$out_file"
if [ "$case_status" -ne 0 ]; then
  echo "expected hosted-size-report success to exit 0, got $case_status" >&2
  exit 1
fi
expect_stdout_exact success "8"
expect_stderr_exact success ""
if [ "$(<"$out_file")" != "8" ]; then
  echo "hosted-size-report wrote unexpected success output file" >&2
  exit 1
fi

empty_file="$tmp_dir/empty.txt"
empty_out="$tmp_dir/empty-out.txt"
: > "$empty_file"
run_case empty "$silt_bin" run hosted-size-report -- "$empty_file" 0 "$empty_out"
if [ "$case_status" -ne 0 ]; then
  echo "expected hosted-size-report empty-file success to exit 0, got $case_status" >&2
  exit 1
fi
expect_stdout_exact empty-file "0"
expect_stderr_exact empty-file ""
if [ "$(<"$empty_out")" != "0" ]; then
  echo "hosted-size-report wrote unexpected empty-file output file" >&2
  exit 1
fi

mismatch_out="$tmp_dir/mismatch.txt"
run_case mismatch "$silt_bin" run hosted-size-report -- "$in_file" 9 "$mismatch_out"
if [ "$case_status" -ne 5 ]; then
  echo "expected hosted-size-report mismatch to exit 5, got $case_status" >&2
  exit 1
fi
expect_stdout_exact mismatch "8"
expect_stderr_exact mismatch $'error: length mismatch\n'
if [ "$(<"$mismatch_out")" != "8" ]; then
  echo "hosted-size-report wrote unexpected mismatch output file" >&2
  exit 1
fi

invalid_out="$tmp_dir/invalid.txt"
run_case invalid "$silt_bin" run hosted-size-report -- "$in_file" nope "$invalid_out"
if [ "$case_status" -ne 4 ]; then
  echo "expected hosted-size-report invalid expected length to exit 4, got $case_status" >&2
  exit 1
fi
expect_stdout_exact "invalid expected" ""
expect_stderr_exact "invalid expected" $'error: invalid expected length\n'
if [ -e "$invalid_out" ]; then
  echo "hosted-size-report wrote a file after invalid expected length" >&2
  exit 1
fi

run_case missing "$silt_bin" run hosted-size-report
if [ "$case_status" -ne 2 ]; then
  echo "expected hosted-size-report without args to exit 2, got $case_status" >&2
  exit 1
fi
expect_stdout_exact missing-args ""
expect_stderr_exact missing-args $'usage: hosted-size-report INPUT EXPECTED_LEN OUTPUT\n'

extra_out="$tmp_dir/extra.txt"
run_case extra "$silt_bin" run hosted-size-report -- "$in_file" 8 "$extra_out" ignored
if [ "$case_status" -ne 2 ]; then
  echo "expected hosted-size-report extra args to exit 2, got $case_status" >&2
  exit 1
fi
expect_stdout_exact extra-args ""
expect_stderr_exact extra-args $'usage: hosted-size-report INPUT EXPECTED_LEN OUTPUT\n'
if [ -e "$extra_out" ]; then
  echo "hosted-size-report wrote a file after extra args" >&2
  exit 1
fi

read_failed_out="$tmp_dir/read-failed.txt"
run_case read_failed "$silt_bin" run hosted-size-report -- "$tmp_dir/missing-input.txt" 0 "$read_failed_out"
if [ "$case_status" -ne 6 ]; then
  echo "expected hosted-size-report missing input to exit 6, got $case_status" >&2
  exit 1
fi
expect_stdout_exact read-failure ""
expect_stderr_exact read-failure $'error: read failed\n'
if [ -e "$read_failed_out" ]; then
  echo "hosted-size-report wrote a file after read failure" >&2
  exit 1
fi

run_case write_failed "$silt_bin" run hosted-size-report -- "$in_file" 8 "$tmp_dir/nope/out.txt"
if [ "$case_status" -ne 3 ]; then
  echo "expected hosted-size-report write failure to exit 3, got $case_status" >&2
  exit 1
fi
expect_stdout_exact write-failure ""
expect_stderr_exact write-failure $'error: write failed\n'

git diff --check
