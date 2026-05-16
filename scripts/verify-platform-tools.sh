#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

if [ "${SILT_SKIP_CABAL_TEST:-0}" != "1" ]; then
  cabal test all
fi
cabal build exe:silt
cabal exec -- silt fmt test/fixtures/format/messy.silt > "$tmpdir/stdout.silt"
diff -u test/fixtures/format/clean.silt "$tmpdir/stdout.silt"
cabal exec -- silt fmt --check test/fixtures/format/clean.silt

printf '(static-bytes greeting"Hi\\x0A")\n' > "$tmpdir/string-messy.silt"
printf '(static-bytes greeting "Hi\\n")\n' > "$tmpdir/string-clean.silt"
cabal exec -- silt fmt "$tmpdir/string-messy.silt" > "$tmpdir/string-out.silt"
diff -u "$tmpdir/string-clean.silt" "$tmpdir/string-out.silt"
cabal exec -- silt fmt --check "$tmpdir/string-clean.silt"
cabal exec -- silt check "$tmpdir/string-clean.silt" >/dev/null

if cabal exec -- silt fmt --check test/fixtures/format/messy.silt >/dev/null 2>&1; then
  echo "expected messy formatter fixture to fail --check" >&2
  exit 1
fi

if cabal exec -- silt fmt --write >/dev/null 2>&1; then
  echo "expected fmt --write without files to fail" >&2
  exit 1
fi

cp test/fixtures/format/messy.silt "$tmpdir/write-one.silt"
cabal exec -- silt fmt --write "$tmpdir/write-one.silt" > "$tmpdir/write-one.out"
test ! -s "$tmpdir/write-one.out"
diff -u test/fixtures/format/clean.silt "$tmpdir/write-one.silt"
cabal exec -- silt fmt --check "$tmpdir/write-one.silt"

cp test/fixtures/lint/bad-parse.silt "$tmpdir/bad-parse.silt"
cp "$tmpdir/bad-parse.silt" "$tmpdir/bad-parse.before"
if cabal exec -- silt fmt --write "$tmpdir/bad-parse.silt" >/dev/null 2>&1; then
  echo "expected fmt --write to fail on malformed source" >&2
  exit 1
fi
cmp "$tmpdir/bad-parse.before" "$tmpdir/bad-parse.silt"

cp test/fixtures/format/messy.silt "$tmpdir/write-a.silt"
cp test/fixtures/format/messy.silt "$tmpdir/write-b.silt"
cabal exec -- silt fmt --write "$tmpdir/write-a.silt" "$tmpdir/write-b.silt"
diff -u test/fixtures/format/clean.silt "$tmpdir/write-a.silt"
diff -u test/fixtures/format/clean.silt "$tmpdir/write-b.silt"

git diff --check
