#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

if [ "${SILT_SKIP_CABAL_TEST:-0}" != "1" ]; then
  cabal test all
fi
cabal build exe:silt

cabal exec -- silt lint test/fixtures/lint/clean.silt >/dev/null

if cabal exec -- silt lint test/fixtures/lint/messy.silt >/dev/null 2>&1; then
  echo "expected lint to reject non-canonical source" >&2
  exit 1
fi

if cabal exec -- silt lint test/fixtures/lint/bad-check.silt >/dev/null 2>&1; then
  echo "expected lint to reject ill-typed source" >&2
  exit 1
fi

grep -q "setfiletype silt" editors/neovim/ftdetect/silt.vim
grep -q "syntax keyword siltDeclaration" editors/neovim/syntax/silt.vim
grep -q "u64-to-nat" editors/neovim/syntax/silt.vim

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
