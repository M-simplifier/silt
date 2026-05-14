#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

if [ "${SILT_SKIP_CABAL_TEST:-0}" != "1" ]; then
  cabal test all
fi
cabal build exe:silt
silt_bin="$(cabal list-bin exe:silt)"

hosted_lf_count_sources=(
  stdlib/core.silt
  stdlib/nat.silt
  stdlib/bytes.silt
  stdlib/text.silt
  stdlib/ascii.silt
  stdlib/ascii-decimal.silt
  stdlib/hosted.silt
  stdlib/hosted-decimal.silt
  examples/hosted-lf-count.silt
)

grep -Fq 'text-count-lf' examples/hosted-lf-count.silt
grep -Fq 'host-status-with-error-text' examples/hosted-lf-count.silt
grep -Fq 'host-write-file-u64-decimal' examples/hosted-lf-count.silt
grep -Fq 'host-write-u64-decimal' examples/hosted-lf-count.silt
"$silt_bin" check "${hosted_lf_count_sources[@]}" >/dev/null

hosted_lf_count_c="$("$silt_bin" emit-c-bundle "${hosted_lf_count_sources[@]}" -- hosted-lf-count-main)"
if ! grep -Fq 'silt_host_arg_count' <<<"$hosted_lf_count_c"; then
  echo "hosted-lf-count did not check process argument count" >&2
  exit 1
fi
if ! grep -Fq 'silt_host_arg_base' <<<"$hosted_lf_count_c"; then
  echo "hosted-lf-count did not read argument text boundaries" >&2
  exit 1
fi
if ! grep -Fq 'silt_host_file_read_base' <<<"$hosted_lf_count_c"; then
  echo "hosted-lf-count did not call the hosted file-read boundary" >&2
  exit 1
fi
if ! grep -Fq 'silt_host_file_read_ok' <<<"$hosted_lf_count_c"; then
  echo "hosted-lf-count did not observe hosted file-read status" >&2
  exit 1
fi
if ! grep -Fq 'silt_layout_HostReadFileResult' <<<"$hosted_lf_count_c"; then
  echo "hosted-lf-count did not use the hosted file-read result layout" >&2
  exit 1
fi
if ! grep -Fq 'for (uint64_t index_' <<<"$hosted_lf_count_c"; then
  echo "hosted-lf-count did not lower the LF count through a length-driven loop" >&2
  exit 1
fi
if ! grep -Fq '(*((uint8_t*)' <<<"$hosted_lf_count_c"; then
  echo "hosted-lf-count did not load bytes through explicit byte pointers" >&2
  exit 1
fi
if ! grep -Fq '== ((uint8_t)10u)' <<<"$hosted_lf_count_c"; then
  echo "hosted-lf-count did not compare loaded bytes against LF" >&2
  exit 1
fi
if ! grep -Fq 'silt_host_file_write_bytes' <<<"$hosted_lf_count_c"; then
  echo "hosted-lf-count did not call the hosted file-write boundary" >&2
  exit 1
fi
if ! grep -Fq 'silt_host_put_byte(byte_' <<<"$hosted_lf_count_c"; then
  echo "hosted-lf-count did not write formatted output to stdout" >&2
  exit 1
fi
if ! grep -Fq 'silt_host_put_error_byte(byte_' <<<"$hosted_lf_count_c"; then
  echo "hosted-lf-count did not write diagnostics to stderr" >&2
  exit 1
fi
if ! grep -Fq '% 10ULL' <<<"$hosted_lf_count_c"; then
  echo "hosted-lf-count did not retain decimal format remainder evidence" >&2
  exit 1
fi
if ! grep -Fq '/ 10ULL' <<<"$hosted_lf_count_c"; then
  echo "hosted-lf-count did not retain decimal format division evidence" >&2
  exit 1
fi
if ! grep -Fq 'silt_cell_hosted_lf_count_file_buffer' <<<"$hosted_lf_count_c"; then
  echo "hosted-lf-count did not retain its file-output formatting buffer" >&2
  exit 1
fi
if ! grep -Fq 'silt_cell_hosted_lf_count_stdout_buffer' <<<"$hosted_lf_count_c"; then
  echo "hosted-lf-count did not retain its stdout formatting buffer" >&2
  exit 1
fi

"$silt_bin" build hosted-lf-count >/dev/null
tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

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
    echo "unexpected hosted-lf-count $label stdout" >&2
    exit 1
  fi
}

expect_stderr_exact() {
  local label="$1"
  local expected="$2"
  if ! printf '%s' "$expected" | cmp -s - "$case_stderr"; then
    echo "unexpected hosted-lf-count $label stderr" >&2
    exit 1
  fi
}

lf_file="$tmp_dir/lf.txt"
lf_out="$tmp_dir/lf-out.txt"
printf 'alpha\nbeta\ngamma\n' >"$lf_file"
run_case lf "$silt_bin" run hosted-lf-count -- "$lf_file" "$lf_out"
if [ "$case_status" -ne 0 ]; then
  echo "expected hosted-lf-count success to exit 0, got $case_status" >&2
  exit 1
fi
expect_stdout_exact lf "3"
expect_stderr_exact lf ""
if ! printf '3' | cmp -s - "$lf_out"; then
  echo "hosted-lf-count wrote unexpected LF count output file" >&2
  exit 1
fi

none_file="$tmp_dir/no-lf.txt"
none_out="$tmp_dir/no-lf-out.txt"
printf 'no newline here' >"$none_file"
run_case no_lf "$silt_bin" run hosted-lf-count -- "$none_file" "$none_out"
if [ "$case_status" -ne 0 ]; then
  echo "expected hosted-lf-count no-LF success to exit 0, got $case_status" >&2
  exit 1
fi
expect_stdout_exact no-lf "0"
expect_stderr_exact no-lf ""
if ! printf '0' | cmp -s - "$none_out"; then
  echo "hosted-lf-count wrote unexpected no-LF output file" >&2
  exit 1
fi

run_case missing "$silt_bin" run hosted-lf-count
if [ "$case_status" -ne 2 ]; then
  echo "expected hosted-lf-count without args to exit 2, got $case_status" >&2
  exit 1
fi
expect_stdout_exact missing-args ""
expect_stderr_exact missing-args $'usage: hosted-lf-count INPUT OUTPUT\n'

extra_out="$tmp_dir/extra.txt"
run_case extra "$silt_bin" run hosted-lf-count -- "$lf_file" "$extra_out" ignored
if [ "$case_status" -ne 2 ]; then
  echo "expected hosted-lf-count extra args to exit 2, got $case_status" >&2
  exit 1
fi
expect_stdout_exact extra-args ""
expect_stderr_exact extra-args $'usage: hosted-lf-count INPUT OUTPUT\n'
if [ -e "$extra_out" ]; then
  echo "hosted-lf-count wrote a file after extra args" >&2
  exit 1
fi

read_failed_out="$tmp_dir/read-failed.txt"
run_case read_failed "$silt_bin" run hosted-lf-count -- "$tmp_dir/missing-input.txt" "$read_failed_out"
if [ "$case_status" -ne 6 ]; then
  echo "expected hosted-lf-count missing input to exit 6, got $case_status" >&2
  exit 1
fi
expect_stdout_exact read-failure ""
expect_stderr_exact read-failure $'error: read failed\n'
if [ -e "$read_failed_out" ]; then
  echo "hosted-lf-count wrote a file after read failure" >&2
  exit 1
fi

run_case write_failed "$silt_bin" run hosted-lf-count -- "$lf_file" "$tmp_dir/nope/out.txt"
if [ "$case_status" -ne 3 ]; then
  echo "expected hosted-lf-count write failure to exit 3, got $case_status" >&2
  exit 1
fi
expect_stdout_exact write-failure ""
expect_stderr_exact write-failure $'error: write failed\n'

git diff --check
