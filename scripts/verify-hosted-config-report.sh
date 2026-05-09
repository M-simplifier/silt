#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

if [ "${SILT_SKIP_CABAL_TEST:-0}" != "1" ]; then
  cabal test all
fi
cabal build exe:silt
silt_bin="$(cabal list-bin exe:silt)"

hosted_config_report_sources=(
  stdlib/core.silt
  stdlib/nat.silt
  stdlib/bytes.silt
  stdlib/text.silt
  stdlib/ascii.silt
  stdlib/ascii-slice.silt
  stdlib/ascii-decimal.silt
  stdlib/hosted.silt
  stdlib/hosted-decimal.silt
  examples/hosted-config-report.silt
)

grep -Fq 'host-status-with-error-text' examples/hosted-config-report.silt
grep -Fq 'host-write-file-u64-decimal' examples/hosted-config-report.silt
grep -Fq 'host-write-u64-decimal' examples/hosted-config-report.silt
"$silt_bin" check "${hosted_config_report_sources[@]}" >/dev/null

hosted_config_report_c="$("$silt_bin" emit-c-bundle "${hosted_config_report_sources[@]}" -- hosted-config-report-main)"
if ! grep -Fq 'silt_host_arg_count' <<<"$hosted_config_report_c"; then
  echo "hosted-config-report did not check process argument count" >&2
  exit 1
fi
if ! grep -Fq 'silt_host_arg_base' <<<"$hosted_config_report_c"; then
  echo "hosted-config-report did not read argument text boundaries" >&2
  exit 1
fi
if ! grep -Fq 'silt_host_file_read_base' <<<"$hosted_config_report_c"; then
  echo "hosted-config-report did not call the hosted file-read boundary" >&2
  exit 1
fi
if ! grep -Fq 'silt_host_file_read_len' <<<"$hosted_config_report_c"; then
  echo "hosted-config-report did not retain hosted file-read length evidence" >&2
  exit 1
fi
if ! grep -Fq 'silt_host_file_read_ok' <<<"$hosted_config_report_c"; then
  echo "hosted-config-report did not observe hosted file-read status" >&2
  exit 1
fi
if ! grep -Fq 'silt_layout_HostReadFileResult' <<<"$hosted_config_report_c"; then
  echo "hosted-config-report did not use the hosted file-read result layout" >&2
  exit 1
fi
if ! grep -Fq 'silt_host_file_write_bytes' <<<"$hosted_config_report_c"; then
  echo "hosted-config-report did not call the hosted file-write boundary" >&2
  exit 1
fi
if ! grep -Fq 'silt_host_put_byte(byte_' <<<"$hosted_config_report_c"; then
  echo "hosted-config-report did not write formatted output to stdout" >&2
  exit 1
fi
if ! grep -Fq 'silt_host_put_error_byte(byte_' <<<"$hosted_config_report_c"; then
  echo "hosted-config-report did not write diagnostics to stderr" >&2
  exit 1
fi
if ! grep -Fq 'silt_layout_TextSplitFirst' <<<"$hosted_config_report_c"; then
  echo "hosted-config-report did not retain text split result evidence" >&2
  exit 1
fi
if ! grep -Fq '== ((uint8_t)58u)' <<<"$hosted_config_report_c"; then
  echo "hosted-config-report did not retain colon split evidence" >&2
  exit 1
fi
if ! grep -Fq 'silt_layout_AsciiTrimState' <<<"$hosted_config_report_c"; then
  echo "hosted-config-report did not retain ASCII trim state evidence" >&2
  exit 1
fi
if ! grep -Fq '9ULL <=' <<<"$hosted_config_report_c"; then
  echo "hosted-config-report did not retain ASCII whitespace lower-bound evidence" >&2
  exit 1
fi
if ! grep -Fq '== ((uint8_t)32u)' <<<"$hosted_config_report_c"; then
  echo "hosted-config-report did not retain ASCII space trim evidence" >&2
  exit 1
fi
if ! grep -Fq 'silt_static_hosted_config_report_key_bytes' <<<"$hosted_config_report_c"; then
  echo "hosted-config-report did not retain static config key evidence" >&2
  exit 1
fi
if ! grep -Fq '* 10ULL) + (((uint64_t)byte_' <<<"$hosted_config_report_c"; then
  echo "hosted-config-report did not retain decimal parse accumulation evidence" >&2
  exit 1
fi
if ! grep -Fq '% 10ULL' <<<"$hosted_config_report_c"; then
  echo "hosted-config-report did not retain decimal format remainder evidence" >&2
  exit 1
fi
if ! grep -Fq '/ 10ULL' <<<"$hosted_config_report_c"; then
  echo "hosted-config-report did not retain decimal format division evidence" >&2
  exit 1
fi
if ! grep -Fq 'silt_cell_hosted_config_report_file_buffer' <<<"$hosted_config_report_c"; then
  echo "hosted-config-report did not retain its file-output formatting buffer" >&2
  exit 1
fi
if ! grep -Fq 'silt_cell_hosted_config_report_stdout_buffer' <<<"$hosted_config_report_c"; then
  echo "hosted-config-report did not retain its stdout formatting buffer" >&2
  exit 1
fi

"$silt_bin" build hosted-config-report >/dev/null
tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT
in_file="$tmp_dir/input.txt"
config_file="$tmp_dir/config.txt"
out_file="$tmp_dir/out.txt"
printf 'SILT_APP' >"$in_file"
printf ' expected : 8\n' >"$config_file"

run_case() {
  local label="$1"
  shift
  case_stdout="$tmp_dir/$label.stdout"
  case_stderr="$tmp_dir/$label.stderr"
  set +e
  "$@" >"$case_stdout" 2>"$case_stderr"
  case_status=$?
  set -e
}

expect_stdout_exact() {
  local label="$1"
  local expected="$2"
  if ! printf '%s' "$expected" | cmp -s - "$case_stdout"; then
    echo "unexpected hosted-config-report $label stdout" >&2
    exit 1
  fi
}

expect_stderr_exact() {
  local label="$1"
  local expected="$2"
  if ! printf '%s' "$expected" | cmp -s - "$case_stderr"; then
    echo "unexpected hosted-config-report $label stderr" >&2
    exit 1
  fi
}

run_case ok "$silt_bin" run hosted-config-report -- "$in_file" "$config_file" "$out_file"
if [ "$case_status" -ne 0 ]; then
  echo "expected hosted-config-report success to exit 0, got $case_status" >&2
  exit 1
fi
expect_stdout_exact success "8"
expect_stderr_exact success ""
if [ "$(<"$out_file")" != "8" ]; then
  echo "hosted-config-report wrote unexpected success output file" >&2
  exit 1
fi

empty_file="$tmp_dir/empty.txt"
empty_config="$tmp_dir/empty-config.txt"
empty_out="$tmp_dir/empty-out.txt"
: >"$empty_file"
printf 'expected: 0\n' >"$empty_config"
run_case empty "$silt_bin" run hosted-config-report -- "$empty_file" "$empty_config" "$empty_out"
if [ "$case_status" -ne 0 ]; then
  echo "expected hosted-config-report empty-file success to exit 0, got $case_status" >&2
  exit 1
fi
expect_stdout_exact empty-file "0"
expect_stderr_exact empty-file ""
if [ "$(<"$empty_out")" != "0" ]; then
  echo "hosted-config-report wrote unexpected empty-file output file" >&2
  exit 1
fi

mismatch_config="$tmp_dir/mismatch-config.txt"
mismatch_out="$tmp_dir/mismatch.txt"
printf 'expected: 9\n' >"$mismatch_config"
run_case mismatch "$silt_bin" run hosted-config-report -- "$in_file" "$mismatch_config" "$mismatch_out"
if [ "$case_status" -ne 5 ]; then
  echo "expected hosted-config-report mismatch to exit 5, got $case_status" >&2
  exit 1
fi
expect_stdout_exact mismatch "8"
expect_stderr_exact mismatch $'error: length mismatch\n'
if [ "$(<"$mismatch_out")" != "8" ]; then
  echo "hosted-config-report wrote unexpected mismatch output file" >&2
  exit 1
fi

invalid_expected_config="$tmp_dir/invalid-expected-config.txt"
invalid_expected_out="$tmp_dir/invalid-expected.txt"
printf 'expected: nope\n' >"$invalid_expected_config"
run_case invalid_expected "$silt_bin" run hosted-config-report -- "$in_file" "$invalid_expected_config" "$invalid_expected_out"
if [ "$case_status" -ne 4 ]; then
  echo "expected hosted-config-report invalid expected length to exit 4, got $case_status" >&2
  exit 1
fi
expect_stdout_exact invalid-expected ""
expect_stderr_exact invalid-expected $'error: invalid expected length\n'
if [ -e "$invalid_expected_out" ]; then
  echo "hosted-config-report wrote a file after invalid expected length" >&2
  exit 1
fi

missing_colon_config="$tmp_dir/missing-colon-config.txt"
missing_colon_out="$tmp_dir/missing-colon.txt"
printf 'expected 8\n' >"$missing_colon_config"
run_case missing_colon "$silt_bin" run hosted-config-report -- "$in_file" "$missing_colon_config" "$missing_colon_out"
if [ "$case_status" -ne 8 ]; then
  echo "expected hosted-config-report missing-colon config to exit 8, got $case_status" >&2
  exit 1
fi
expect_stdout_exact missing-colon ""
expect_stderr_exact missing-colon $'error: invalid config\n'
if [ -e "$missing_colon_out" ]; then
  echo "hosted-config-report wrote a file after invalid config" >&2
  exit 1
fi

wrong_key_config="$tmp_dir/wrong-key-config.txt"
wrong_key_out="$tmp_dir/wrong-key.txt"
printf 'actual: 8\n' >"$wrong_key_config"
run_case wrong_key "$silt_bin" run hosted-config-report -- "$in_file" "$wrong_key_config" "$wrong_key_out"
if [ "$case_status" -ne 9 ]; then
  echo "expected hosted-config-report wrong-key config to exit 9, got $case_status" >&2
  exit 1
fi
expect_stdout_exact wrong-key ""
expect_stderr_exact wrong-key $'error: invalid config key\n'
if [ -e "$wrong_key_out" ]; then
  echo "hosted-config-report wrote a file after invalid config key" >&2
  exit 1
fi

run_case missing "$silt_bin" run hosted-config-report
if [ "$case_status" -ne 2 ]; then
  echo "expected hosted-config-report without args to exit 2, got $case_status" >&2
  exit 1
fi
expect_stdout_exact missing-args ""
expect_stderr_exact missing-args $'usage: hosted-config-report INPUT CONFIG OUTPUT\n'

extra_out="$tmp_dir/extra.txt"
run_case extra "$silt_bin" run hosted-config-report -- "$in_file" "$config_file" "$extra_out" ignored
if [ "$case_status" -ne 2 ]; then
  echo "expected hosted-config-report extra args to exit 2, got $case_status" >&2
  exit 1
fi
expect_stdout_exact extra-args ""
expect_stderr_exact extra-args $'usage: hosted-config-report INPUT CONFIG OUTPUT\n'
if [ -e "$extra_out" ]; then
  echo "hosted-config-report wrote a file after extra args" >&2
  exit 1
fi

input_read_failed_out="$tmp_dir/input-read-failed.txt"
run_case input_read_failed "$silt_bin" run hosted-config-report -- "$tmp_dir/missing-input.txt" "$config_file" "$input_read_failed_out"
if [ "$case_status" -ne 6 ]; then
  echo "expected hosted-config-report missing input to exit 6, got $case_status" >&2
  exit 1
fi
expect_stdout_exact input-read-failure ""
expect_stderr_exact input-read-failure $'error: input read failed\n'
if [ -e "$input_read_failed_out" ]; then
  echo "hosted-config-report wrote a file after input read failure" >&2
  exit 1
fi

config_read_failed_out="$tmp_dir/config-read-failed.txt"
run_case config_read_failed "$silt_bin" run hosted-config-report -- "$in_file" "$tmp_dir/missing-config.txt" "$config_read_failed_out"
if [ "$case_status" -ne 7 ]; then
  echo "expected hosted-config-report missing config to exit 7, got $case_status" >&2
  exit 1
fi
expect_stdout_exact config-read-failure ""
expect_stderr_exact config-read-failure $'error: config read failed\n'
if [ -e "$config_read_failed_out" ]; then
  echo "hosted-config-report wrote a file after config read failure" >&2
  exit 1
fi

run_case write_failed "$silt_bin" run hosted-config-report -- "$in_file" "$config_file" "$tmp_dir/nope/out.txt"
if [ "$case_status" -ne 3 ]; then
  echo "expected hosted-config-report write failure to exit 3, got $case_status" >&2
  exit 1
fi
expect_stdout_exact write-failure ""
expect_stderr_exact write-failure $'error: write failed\n'

git diff --check
