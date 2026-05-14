#!/usr/bin/env bash

hosted_verify_setup() {
  repo_root="$(cd "$(dirname "${BASH_SOURCE[1]}")/.." && pwd)"
  cd "$repo_root"

  if [ "${SILT_SKIP_CABAL_TEST:-0}" != "1" ]; then
    cabal test all
  fi
  cabal build exe:silt
  silt_bin="$(cabal list-bin exe:silt)"
}

fail_verify() {
  echo "$1" >&2
  exit 1
}

require_file_contains() {
  local file="$1"
  local needle="$2"
  local message="$3"
  grep -Fq "$needle" "$file" || fail_verify "$message"
}

require_c_fragment() {
  local haystack="$1"
  local needle="$2"
  local message="$3"
  grep -Fq "$needle" <<<"$haystack" || fail_verify "$message"
}

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

expect_status() {
  local label="$1"
  local expected="$2"
  local app="${hosted_case_app:-hosted app}"
  if [ "$case_status" -ne "$expected" ]; then
    fail_verify "expected $app $label to exit $expected, got $case_status"
  fi
}

expect_stdout_exact() {
  local label="$1"
  local expected="$2"
  local app="${hosted_case_app:-hosted app}"
  if ! printf '%s' "$expected" | cmp -s - "$case_stdout"; then
    fail_verify "unexpected $app $label stdout"
  fi
}

expect_stderr_exact() {
  local label="$1"
  local expected="$2"
  local app="${hosted_case_app:-hosted app}"
  if ! printf '%s' "$expected" | cmp -s - "$case_stderr"; then
    fail_verify "unexpected $app $label stderr"
  fi
}

expect_file_exact() {
  local label="$1"
  local file="$2"
  local expected="$3"
  local app="${hosted_case_app:-hosted app}"
  if ! printf '%s' "$expected" | cmp -s - "$file"; then
    fail_verify "$app wrote unexpected $label output file"
  fi
}

expect_file_absent() {
  local label="$1"
  local file="$2"
  local app="${hosted_case_app:-hosted app}"
  if [ -e "$file" ]; then
    fail_verify "$app wrote a file after $label"
  fi
}
