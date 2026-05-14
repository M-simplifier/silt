# Appendix B: コマンドリファレンス

この付録は、本文で使った主要コマンドをまとめたものです。Siltを読むときは、`check`、`norm`、生成、検証を分けて使います。

## package spine

```bash
cabal run silt -- new hello-silt
cabal run silt -- build
cabal run silt -- run
cabal run silt -- test
cabal run silt -- doc
cabal run silt -- build hosted-hello
cabal run silt -- run hosted-hello
cabal run silt -- build hosted-echo
cabal run silt -- run hosted-echo -- SILT_ARG
cabal run silt -- build hosted-env
SILT_HOSTED_ENV=SILT_ENV_VALUE cabal run silt -- run hosted-env
cabal run silt -- build hosted-exit
cabal run silt -- run hosted-exit -- ok
cabal run silt -- build hosted-write-file
cabal run silt -- run hosted-write-file -- /tmp/silt-hosted-file.txt
cabal run silt -- build hosted-cat
cabal run silt -- run hosted-cat -- /tmp/silt-hosted-file.txt
cabal run silt -- build hosted-size-report
cabal run silt -- run hosted-size-report -- /tmp/silt-hosted-file.txt 10 /tmp/silt-size-report.txt
cabal run silt -- build hosted-config-report
printf 'expected: 10\n' >/tmp/silt-size-config.txt
cabal run silt -- run hosted-config-report -- /tmp/silt-hosted-file.txt /tmp/silt-size-config.txt /tmp/silt-config-report.txt
cabal run silt -- test
cabal run silt -- test ascii-slice-test
cabal run silt -- test ascii-decimal-u64-test
cabal run silt -- test ascii-decimal-u64-format-test
```

`silt new NAME` は現在のdirectoryに `Silt.pkg` がなくても新しいpackage directoryを作ります。それ以外のpackage commandはカレントディレクトリの `Silt.pkg` を読みます。現在のpublic claimは、単一local package、明示的な `bin` / `test` target、no-argument hosted entry function、`silt new NAME` による単純なscaffold生成、`silt doc` によるmanifest由来HTML生成、`silt run [TARGET] -- ARG...` によるhosted process argumentの受け渡し、名前を指定した単一のenvironment lookup、bin entryの結果をprocess statusとして伝播すること、明示的な `TextView` path/bodyによるfirst-orderなhosted file write、明示的な `TextView` pathからhost-ownedな `TextView` へ読むfirst-orderなhosted file readとread-status観測、`ByteSlice` / `TextView` 上のbyte-wise equality、prefix check、suffix check、`U8` 上のASCII byte predicate、明示的な `ByteSlice` / `TextView` 上の狭いall-ASCII class check、空入力、非数字、overflowを拒否する狭いASCII decimal `U64` parser、そしてcaller-providedな `AsciiDecimalU64Buffer` にASCII decimal `U64` を書いて明示的な `TextView` として返すformatterに限られます。root packageには、stdlib seedの `TextView` と `host-write-text` で `SILT` を出力する `hosted-hello`、`argv[1]` を出力する `hosted-echo`、`SILT_HOSTED_ENV` を出力する `hosted-env`、`argv[1]` の有無をprocess statusで返す `hosted-exit`、`argv[1]` のpathへ固定bodyを書く `hosted-write-file`、`argv[1]` のpathから読んだ内容をstdoutへ書く `hosted-cat`、process args、file readとread-status観測、ASCII decimal parse/format、file write、stdout、process statusを一つの経路で組み合わせる `hosted-size-report`、複数file read、first-byte split、ASCII whitespace trim、static key compare、ASCII decimal parse/format、file write、stdout、stderr diagnostics、process statusを一つの経路で組み合わせる `hosted-config-report`、stdlibの正規化例を確認する `stdlib-test`、静的byte-backed textの等価比較を確認する `text-eq-test`、prefixを確認する `text-prefix-test`、suffixを確認する `text-suffix-test`、ASCII byte predicateを確認する `ascii-test`、ASCII slice/text predicateを確認する `ascii-slice-test`、ASCII decimal parseを確認する `ascii-decimal-u64-test`、ASCII decimal formatを確認する `ascii-decimal-u64-format-test` が含まれます。dependency、workspace、lockfile、package publishing、package resolution、selectable package template、source comment extraction、type-signature docs、cross-package docs、environment enumeration/mutation、現在のsuccess/failure statusを超える詳細なfile-read error分類、append mode、directory operation、path library、process spawning、signals、stdout/stderr abstraction、general hosted IO、multi-entry config format、generic CLI/config parser、Unicode category、locale-sensitive behavior、case conversion、UTF-8 validation、動的文字列、現在の狭いall-ASCII class check、ASCII decimal `U64` parser、ASCII decimal `U64` formatterを超えるsubstring/search/general scanning API、符号、基数prefix、separator、whitespace trimming、詳細なparse error分類、符号付きformat、radix format、padding、alignment、locale formatting、parser/formatter combinator libraryはまだclaimしません。

## formatter

```bash
cabal run silt -- fmt examples/data.silt
cabal run silt -- fmt --check test/fixtures/format/clean.silt
```

`fmt` は、現在のS式source subsetをcanonicalな形に整形します。`--check` は入力がすでにその形かどうかだけを確認します。

## linter / editor files

```bash
cabal run silt -- lint test/fixtures/lint/clean.silt
scripts/verify-editor-tools.sh
```

`lint` は、canonical formatting、source bundle parsing、checker diagnosticsをまとめて確認します。`editors/neovim/` には、現在のpublic surface向けの軽量なfiletype/syntax fileがあります。これはLSP、semantic highlighting、formatter adapter、package-manager pluginではありません。

## 型検査

```bash
cabal run silt -- check examples/identity.silt
cabal run silt -- check examples/limine.silt
```

## 正規化

```bash
cabal run silt -- norm examples/stage1.silt three
cabal run silt -- norm examples/limine.silt kernel-allocator-handoff-sample
cabal run silt -- norm examples/limine.silt kernel-allocator-handoff-sample-ready
```

## C生成

```bash
cabal run silt -- emit-c examples/stage1.silt add
cabal run silt -- emit-freestanding-c examples/limine.silt limine-entry
```

## contract確認

```bash
cabal run silt -- abi-contracts examples/freestanding.silt
cabal run silt -- target-contracts examples/limine.silt
cabal run silt -- boot-contracts examples/limine.silt
```

## backend検証

```bash
cabal test all
scripts/verify-platform-tools.sh
scripts/verify-editor-tools.sh
scripts/verify-package-spine.sh
scripts/verify-stdlib-hosted-seed.sh
scripts/verify-hosted-args.sh
scripts/verify-hosted-env.sh
scripts/verify-hosted-exit.sh
scripts/verify-hosted-file-write.sh
scripts/verify-hosted-file-read.sh
scripts/verify-text-eq.sh
scripts/verify-text-prefix.sh
scripts/verify-text-suffix.sh
scripts/verify-text-scan.sh
scripts/verify-text-lines.sh
scripts/verify-text-count.sh
scripts/verify-ascii-predicates.sh
scripts/verify-ascii-slice-predicates.sh
scripts/verify-ascii-trim.sh
scripts/verify-ascii-decimal-u64.sh
scripts/verify-ascii-decimal-u64-format.sh
scripts/verify-text-view-helpers.sh
scripts/verify-stage0-backend.sh
scripts/verify-freestanding-backend.sh
scripts/verify-x86_64-elf-backend.sh
scripts/verify-limine-bridge.sh
scripts/verify-stdlib-core-combinators.sh
scripts/verify-hosted-size-report.sh
scripts/verify-hosted-config-report.sh
scripts/verify-hosted-lf-count.sh
```

## package CLI

```bash
cabal run silt -- new hello-silt
cabal run silt -- build
cabal run silt -- build hosted-hello
cabal run silt -- run hosted-echo -- SILT_ARG
cabal run silt -- build hosted-size-report
cabal run silt -- run hosted-size-report -- /tmp/silt-hosted-file.txt 10 /tmp/silt-size-report.txt
cabal run silt -- build hosted-config-report
printf 'expected: 10\n' >/tmp/silt-size-config.txt
cabal run silt -- run hosted-config-report -- /tmp/silt-hosted-file.txt /tmp/silt-size-config.txt /tmp/silt-config-report.txt
cabal run silt -- build hosted-lf-count
cabal run silt -- run hosted-lf-count -- /tmp/silt-hosted-file.txt /tmp/silt-lf-count.txt
cabal run silt -- test
cabal run silt -- test stdlib-test
cabal run silt -- doc
cabal run silt -- test text-eq-test
cabal run silt -- test text-prefix-test
cabal run silt -- test text-suffix-test
cabal run silt -- test text-scan-test
cabal run silt -- test text-line-test
cabal run silt -- test text-count-test
cabal run silt -- test ascii-test
cabal run silt -- test ascii-slice-test
cabal run silt -- test ascii-trim-test
cabal run silt -- test ascii-decimal-u64-test
cabal run silt -- test ascii-decimal-u64-format-test
```

## QEMU smoke

```bash
scripts/verify-limine-qemu-nix.sh
scripts/verify-limine-panic-qemu-nix.sh
```

`check` は型の約束を確認します。`norm` は値がどこまで具体化されるかを見ます。生成コマンドはbackendの出力を見ます。検証scriptとQEMU smokeは、Siltの外側に出た生成物が期待した形で残っているかを確認します。
