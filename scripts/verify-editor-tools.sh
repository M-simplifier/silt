#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

if [ "${SILT_SKIP_CABAL_TEST:-0}" != "1" ]; then
  cabal test all
fi
cabal build exe:silt

cabal exec -- silt lint test/fixtures/lint/clean.silt >/dev/null
diagnostics_json="$(cabal exec -- silt diagnostics --json test/fixtures/lint/clean.silt)"
grep -q '"schema": "silt.diagnostics.v0"' <<<"$diagnostics_json"
grep -q '"diagnostics": \[' <<<"$diagnostics_json"
if grep -q '"severity": "error"' <<<"$diagnostics_json"; then
  echo "expected clean diagnostics JSON to contain no errors" >&2
  exit 1
fi

if cabal exec -- silt lint test/fixtures/lint/messy.silt >/dev/null 2>&1; then
  echo "expected lint to reject non-canonical source" >&2
  exit 1
fi
set +e
messy_diagnostics_json="$(cabal exec -- silt diagnostics --json test/fixtures/lint/messy.silt 2>/dev/null)"
messy_diagnostics_status=$?
set -e
if [ "$messy_diagnostics_status" -eq 0 ]; then
  echo "expected diagnostics JSON to reject non-canonical source" >&2
  exit 1
fi
grep -q '"path": "test/fixtures/lint/messy.silt"' <<<"$messy_diagnostics_json"
grep -q '"message": "not canonical; run silt fmt"' <<<"$messy_diagnostics_json"
grep -q '"severity": "error"' <<<"$messy_diagnostics_json"

if cabal exec -- silt lint test/fixtures/lint/bad-check.silt >/dev/null 2>&1; then
  echo "expected lint to reject ill-typed source" >&2
  exit 1
fi
set +e
bad_check_diagnostics_json="$(cabal exec -- silt diagnostics --json test/fixtures/lint/bad-check.silt 2>/dev/null)"
bad_check_diagnostics_status=$?
set -e
if [ "$bad_check_diagnostics_status" -eq 0 ]; then
  echo "expected diagnostics JSON to reject ill-typed source" >&2
  exit 1
fi
grep -q '"path": null' <<<"$bad_check_diagnostics_json"
grep -q 'type mismatch' <<<"$bad_check_diagnostics_json"
grep -q '"severity": "error"' <<<"$bad_check_diagnostics_json"

grep -q "setfiletype silt" editors/neovim/ftdetect/silt.vim
grep -q "syntax keyword siltDeclaration" editors/neovim/syntax/silt.vim
grep -q "u64-to-nat" editors/neovim/syntax/silt.vim
grep -q "list-elim" editors/neovim/syntax/silt.vim

if command -v nvim >/dev/null 2>&1; then
  nvim --headless -u NONE \
    --cmd "set runtimepath^=$repo_root/editors/neovim" \
    +'filetype on' \
    +'syntax on' \
    +'edit examples/hosted-hello.silt' \
    +'if &filetype !=# "silt" | cquit | endif' \
    +'quit'
fi

git diff --check
