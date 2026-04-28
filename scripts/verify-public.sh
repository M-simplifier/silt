#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

scripts/build-public-site.sh
scripts/verify-silt-book.sh

local_user='ma''saya'
local_project='free-''exp'
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
repo_cycle='cam''paign'
run_mode='phase-''run'
admin_tool='su''do'
deny_terms="(${home_path}|${local_user}|${local_project}|${ai_vendor}|${ai_chat}|${ai_agent}|${sensitive_word}|${classified_jp}|${chat_jp}|${conversation_jp}|${continue_jp}|${admin_tool}|${repo_cycle}|${run_mode}|${process_word})"

if grep -RInE "$deny_terms" \
  README.md STATUS.md CONTRIBUTING.md LICENSE silt.cabal site/src site/static site/package.json site/spago.yaml site/spago.lock book .github scripts/build-public-site.sh; then
  echo "public files contain local or non-public coordination terms" >&2
  exit 1
fi

if grep -RInE '(production-ready|full kernel|complete allocator|memory-safe|formally verified compiler|guarantees memory safety)' \
  README.md STATUS.md site/src site/static book/src out/site; then
  echo "public files contain over-broad maturity or safety claims" >&2
  exit 1
fi

for expected in \
  "Low-level facts, lifted into typed values." \
  "SILT_ALLOC_HANDOFF" \
  "not a production compiler" \
  "not self-hosted" \
  "no general allocator or kernel"; do
  if ! grep -RIn "$expected" README.md STATUS.md CONTRIBUTING.md site book/src out/site >/dev/null; then
    echo "missing expected public boundary text: $expected" >&2
    exit 1
  fi
done

if git ls-files --others --exclude-standard | grep -E '^(site/\.spago/|site/output/|out/|dist-newstyle/)' >/dev/null; then
  echo "generated build artifacts are not ignored" >&2
  exit 1
fi

echo "Silt public artifact verification passed"
