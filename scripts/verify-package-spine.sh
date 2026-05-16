#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

if [ "${SILT_SKIP_CABAL_TEST:-0}" != "1" ]; then
  cabal test all
fi
cabal build exe:silt
silt_bin="$(cabal list-bin exe:silt)"

rm -rf out/silt/doc test/fixtures/packages/hello/out test/fixtures/packages/failing/out
tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

(
  cd "$tmp_dir"
  "$silt_bin" new hello-new
  test -f hello-new/Silt.pkg
  test -f hello-new/src/main.silt
  test -f hello-new/tests/main.silt
  "$silt_bin" fmt --check hello-new/Silt.pkg hello-new/src/main.silt hello-new/tests/main.silt
  : > occupied-file
  if "$silt_bin" new hello-new; then
    echo "expected silt new to reject an existing package path" >&2
    exit 1
  fi
  if "$silt_bin" new occupied-file; then
    echo "expected silt new to reject an existing file path" >&2
    exit 1
  fi
  if "$silt_bin" new .; then
    echo "expected silt new to reject '.'" >&2
    exit 1
  fi
  if "$silt_bin" new ..; then
    echo "expected silt new to reject '..'" >&2
    exit 1
  fi
  if "$silt_bin" new bad/name; then
    echo "expected silt new to reject package names containing '/'" >&2
    exit 1
  fi
  if "$silt_bin" new 'bad\name'; then
    echo "expected silt new to reject package names containing '\\'" >&2
    exit 1
  fi
  if "$silt_bin" new "bad name"; then
    echo "expected silt new to reject package names containing spaces" >&2
    exit 1
  fi
  if "$silt_bin" new "bad(name)"; then
    echo "expected silt new to reject package names containing S-expression delimiters" >&2
    exit 1
  fi
  if "$silt_bin" new 'bad"name'; then
    echo "expected silt new to reject package names containing quote delimiters" >&2
    exit 1
  fi
  if "$silt_bin" new; then
    echo "expected silt new without a name to fail" >&2
    exit 1
  fi
  if "$silt_bin" new hello-new extra; then
    echo "expected silt new with extra arguments to fail" >&2
    exit 1
  fi
  if "$silt_bin" doc; then
    echo "expected silt doc without Silt.pkg to fail" >&2
    exit 1
  fi
  if "$silt_bin" doc extra; then
    echo "expected silt doc with extra arguments to fail" >&2
    exit 1
  fi
  (
    cd hello-new
    "$silt_bin" build
    test -x out/silt/debug/hello-new
    "$silt_bin" run
    "$silt_bin" doc
    test -f out/silt/doc/index.html
    grep -Fq '<h1>hello-new</h1>' out/silt/doc/index.html
    grep -Fq '<td><code>bin</code></td>' out/silt/doc/index.html
    grep -Fq '<td><code>app-main</code></td>' out/silt/doc/index.html
    grep -Fq '<td><code>hello-new-test</code></td>' out/silt/doc/index.html
    grep -Fq '<code>tests/main.silt</code>' out/silt/doc/index.html
    if "$silt_bin" doc extra; then
      echo "expected silt doc with extra arguments to fail inside a package" >&2
      exit 1
    fi
    new_test_output="$("$silt_bin" test)"
    if ! grep -Fq 'PASS [hello-new-test]' <<<"$new_test_output"; then
      echo "new package test did not report generated test success" >&2
      echo "$new_test_output" >&2
      exit 1
    fi
    if ! grep -Fq 'silt package tests: 1 passed' <<<"$new_test_output"; then
      echo "new package test did not report one passing test" >&2
      echo "$new_test_output" >&2
      exit 1
    fi
  )
)

mkdir "$tmp_dir/escape-doc"
cat > "$tmp_dir/escape-doc/Silt.pkg" <<'PKG'
(package pkg&<>'
  (bin target&<>' (sources src/source&<>'.silt) (entry entry&<>')))
PKG
(
  cd "$tmp_dir/escape-doc"
  "$silt_bin" doc
  test -f out/silt/doc/index.html
  grep -Fq "<h1>pkg&amp;&lt;&gt;&#39;</h1>" out/silt/doc/index.html
  grep -Fq "<td><code>target&amp;&lt;&gt;&#39;</code></td>" out/silt/doc/index.html
  grep -Fq "<td><code>entry&amp;&lt;&gt;&#39;</code></td>" out/silt/doc/index.html
  grep -Fq "<code>src/source&amp;&lt;&gt;&#39;.silt</code>" out/silt/doc/index.html
)

"$silt_bin" doc
test -f out/silt/doc/index.html
grep -Fq '<h1>silt-platform</h1>' out/silt/doc/index.html
grep -Fq '<td><code>hosted-size-report</code></td>' out/silt/doc/index.html
grep -Fq '<td><code>hosted-size-report-main</code></td>' out/silt/doc/index.html
grep -Fq '<code>stdlib/hosted-decimal.silt</code>' out/silt/doc/index.html
grep -Fq '<code>examples/hosted-size-report.silt</code>' out/silt/doc/index.html
grep -Fq '<td><code>hosted-config-report</code></td>' out/silt/doc/index.html
grep -Fq '<td><code>hosted-config-report-main</code></td>' out/silt/doc/index.html
grep -Fq '<code>examples/hosted-config-report.silt</code>' out/silt/doc/index.html
grep -Fq '<td><code>hosted-copy</code></td>' out/silt/doc/index.html
grep -Fq '<td><code>hosted-copy-main</code></td>' out/silt/doc/index.html
grep -Fq '<code>examples/hosted-copy.silt</code>' out/silt/doc/index.html
grep -Fq '<td><code>hosted-ascii-trim</code></td>' out/silt/doc/index.html
grep -Fq '<td><code>hosted-ascii-trim-main</code></td>' out/silt/doc/index.html
grep -Fq '<code>examples/hosted-ascii-trim.silt</code>' out/silt/doc/index.html
grep -Fq '<td><code>hosted-stdin-lf-count</code></td>' out/silt/doc/index.html
grep -Fq '<td><code>hosted-stdin-lf-count-main</code></td>' out/silt/doc/index.html
grep -Fq '<code>examples/hosted-stdin-lf-count.silt</code>' out/silt/doc/index.html
grep -Fq '<td><code>hosted-byte-drop</code></td>' out/silt/doc/index.html
grep -Fq '<td><code>hosted-byte-drop-main</code></td>' out/silt/doc/index.html
grep -Fq '<code>examples/hosted-byte-drop.silt</code>' out/silt/doc/index.html
grep -Fq '<td><code>hosted-source-hygiene</code></td>' out/silt/doc/index.html
grep -Fq '<td><code>hosted-source-hygiene-main</code></td>' out/silt/doc/index.html
grep -Fq '<code>examples/hosted-source-hygiene.silt</code>' out/silt/doc/index.html
grep -Fq '<td><code>list-recursion-test</code></td>' out/silt/doc/index.html
grep -Fq '<code>examples/list-recursion.silt</code>' out/silt/doc/index.html

(
  cd test/fixtures/packages/hello
  "$silt_bin" build
  test -x out/silt/debug/hello
  "$silt_bin" build hello
  "$silt_bin" run
  "$silt_bin" doc
  test -f out/silt/doc/index.html
  grep -Fq '<h1>hello</h1>' out/silt/doc/index.html
  grep -Fq '<td><code>hello-test</code></td>' out/silt/doc/index.html
  grep -Fq '<td><code>app-main</code></td>' out/silt/doc/index.html
  "$silt_bin" test
  test_output="$("$silt_bin" test hello-test)"
  if ! grep -Fq 'PASS [hello-test]' <<<"$test_output"; then
    echo "selected package test did not report hello-test success" >&2
    echo "$test_output" >&2
    exit 1
  fi
  if ! grep -Fq 'silt package tests: 1 passed' <<<"$test_output"; then
    echo "selected package test did not report one passing test" >&2
    echo "$test_output" >&2
    exit 1
  fi
  if "$silt_bin" test hello; then
    echo "expected bin target selection through silt test to fail" >&2
    exit 1
  fi
  if "$silt_bin" test missing-test; then
    echo "expected unknown test target selection to fail" >&2
    exit 1
  fi
  if "$silt_bin" test hello-test extra; then
    echo "expected unsupported extra silt test args to fail" >&2
    exit 1
  fi
)

(
  cd test/fixtures/packages/failing
  if "$silt_bin" test; then
    echo "expected failing package test to fail" >&2
    exit 1
  fi
  if "$silt_bin" test failing-test; then
    echo "expected selected failing package test to fail" >&2
    exit 1
  fi
)

git diff --check
