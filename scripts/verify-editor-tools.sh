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

send_lsp_message() {
  local body="$1"
  local byte_count
  byte_count="$(printf '%s' "$body" | wc -c | tr -d ' ')"
  printf 'Content-Length: %s\r\n\r\n%s' "$byte_count" "$body"
}

lsp_initialize='{"jsonrpc":"2.0","id":1,"method":"initialize","params":{}}'
lsp_initialized='{"jsonrpc":"2.0","method":"initialized","params":{}}'
lsp_did_open='{"jsonrpc":"2.0","method":"textDocument/didOpen","params":{"textDocument":{"uri":"file:///tmp/silt-lsp-messy.silt","languageId":"silt","version":1,"text":"(claim id(Pi((A 0 Type)(x A))A))\n(def id(fn((A 0 Type)(x A))x))\n"}}}'
lsp_did_change='{"jsonrpc":"2.0","method":"textDocument/didChange","params":{"textDocument":{"uri":"file:///tmp/silt-lsp-messy.silt","version":2},"contentChanges":[{"text":"(claim bad U64)\n\n(def bad True)\n"}]}}'
lsp_did_close='{"jsonrpc":"2.0","method":"textDocument/didClose","params":{"textDocument":{"uri":"file:///tmp/silt-lsp-messy.silt"}}}'
lsp_unicode_uri="$(printf 'file:///tmp/silt-lsp-\303\251.silt')"
lsp_did_open_unicode="{\"jsonrpc\":\"2.0\",\"method\":\"textDocument/didOpen\",\"params\":{\"textDocument\":{\"uri\":\"$lsp_unicode_uri\",\"languageId\":\"silt\",\"version\":1,\"text\":\"(claim ok U64)\\n\\n(def ok (u64 1))\\n\"}}}"
lsp_shutdown='{"jsonrpc":"2.0","id":2,"method":"shutdown","params":null}'
lsp_exit='{"jsonrpc":"2.0","method":"exit","params":null}'

lsp_output="$(
  {
    send_lsp_message "$lsp_initialize"
    send_lsp_message "$lsp_initialized"
    send_lsp_message "$lsp_did_open"
    send_lsp_message "$lsp_did_change"
    send_lsp_message "$lsp_did_close"
    send_lsp_message "$lsp_did_open_unicode"
    send_lsp_message "$lsp_shutdown"
    send_lsp_message "$lsp_exit"
  } | cabal exec -- silt lsp
)"
grep -q 'Content-Length:' <<<"$lsp_output"
grep -q '"id":1' <<<"$lsp_output"
grep -q '"textDocumentSync":{"openClose":true,"change":1}' <<<"$lsp_output"
grep -q '"method":"textDocument/publishDiagnostics"' <<<"$lsp_output"
grep -q '"uri":"file:///tmp/silt-lsp-messy.silt"' <<<"$lsp_output"
grep -q '"message":"not canonical; run silt fmt"' <<<"$lsp_output"
grep -q 'type mismatch' <<<"$lsp_output"
grep -q '"diagnostics":\[\]' <<<"$lsp_output"
grep -q 'silt-lsp-' <<<"$lsp_output"
grep -q '"id":2' <<<"$lsp_output"

grep -q "setfiletype silt" editors/neovim/ftdetect/silt.vim
grep -q "syntax keyword siltDeclaration" editors/neovim/syntax/silt.vim
grep -q "syntax region siltString" editors/neovim/syntax/silt.vim
grep -q "u64-to-nat" editors/neovim/syntax/silt.vim
grep -q "list-elim" editors/neovim/syntax/silt.vim
grep -q "list-any" editors/neovim/syntax/silt.vim
grep -q "list-all" editors/neovim/syntax/silt.vim
grep -q "list-find" editors/neovim/syntax/silt.vim
grep -q "list-count" editors/neovim/syntax/silt.vim
grep -q "list-append" editors/neovim/syntax/silt.vim
grep -q "list-filter" editors/neovim/syntax/silt.vim
grep -q "list-reverse" editors/neovim/syntax/silt.vim
grep -q "byte-slice-find-slice" editors/neovim/syntax/silt.vim
grep -q "byte-slice-contains-slice" editors/neovim/syntax/silt.vim
grep -q "text-find-text" editors/neovim/syntax/silt.vim
grep -q "text-contains-text" editors/neovim/syntax/silt.vim

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
