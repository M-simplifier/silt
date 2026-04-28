#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

if ! command -v mdbook >/dev/null 2>&1; then
  echo "mdbook is required to verify the Silt Book" >&2
  exit 1
fi

local_user='ma''saya'
home_path='/''home/'
ai_vendor='Open''AI'
ai_chat='Chat''GPT'
ai_agent='Co''dex'
process_word='pro''ducer'
sensitive_word='sec''ret'
classified_jp='機''密'
chat_jp='チャ''ット'
conversation_jp='会''話'
continue_jp='継''続'
admin_tool='su''do'
deny_terms="(${home_path}|${local_user}|${ai_vendor}|${ai_chat}|${ai_agent}|${sensitive_word}|${classified_jp}|${chat_jp}|${conversation_jp}|${continue_jp}|${admin_tool}|${process_word})"
rust_scope='Rustの''The Book'
rust_book='Rust ''Book'
the_book='The ''Book'
research_note='調査''メモ'
outline_note='構成''プロット'
publication_note='公開''・CI'
pages_note='GitHub ''Pages'
serve_note='mdBook ''serve'
build_note='verify-''silt-book'
phase_note='現在''のフェーズ'
run_cycle='cam''paign'
gate_cycle='mile''stone'
editorial_terms="(${rust_scope}|${rust_book}|${the_book}|${research_note}|${outline_note}|${publication_note}|${pages_note}|${serve_note}|${build_note}|${phase_note}|${run_cycle}|${gate_cycle})"

mdbook build book

test -f out/book/index.html
test -f out/book/print.html

if grep -RInE "$deny_terms" \
  book .github/workflows/book.yml; then
  echo "public Silt Book files contain local or non-public coordination terms" >&2
  exit 1
fi

if grep -RInE "$editorial_terms" \
  book/src; then
  echo "reader-facing Silt Book files contain editorial scaffolding or process terms" >&2
  exit 1
fi

if ! grep -RIn "SILT_ALLOC_HANDOFF" book/src >/dev/null; then
  echo "Silt Book should mention the allocator handoff marker" >&2
  exit 1
fi

echo "Silt Book verification passed"
