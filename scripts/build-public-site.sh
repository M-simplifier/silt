#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

SPAGO="$ROOT/site/node_modules/.bin/spago"
if [ ! -x "$SPAGO" ]; then
  SPAGO="$(command -v spago || true)"
fi

if [ -z "$SPAGO" ]; then
  echo "spago is required to build the Silt site" >&2
  exit 1
fi

if ! command -v mdbook >/dev/null 2>&1; then
  echo "mdbook is required to build the Silt Book" >&2
  exit 1
fi

rm -rf out/site out/book

(
  cd site
  "$SPAGO" run -m Main
)

cp -R site/static/. out/site/

mdbook build book
mkdir -p out/site/book
cp -R out/book/. out/site/book/

touch out/site/.nojekyll

test -f out/site/index.html
test -f out/site/book/index.html
test -f out/site/book/print.html
