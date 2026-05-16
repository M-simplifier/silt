# 20. Siltが保証すること

Siltの保証は、一つの大きな安全性主張ではなく、いくつかの層に分かれています。

この章では、この本で扱ったコードを読むときに、何が確認され、何が確認されないのかを整理します。ここを曖昧にしないことが、Siltを安心して強くしていくための条件です。

## 言語内で確認されること

- S式で依存型コアを書く
- `claim` / `def` で明示的なトップレベル境界を作る
- 数量 `0` / `1` / `omega` で値の使用を制御する
- `Eff pre post A` で副作用の状態遷移を書く
- `U8` / `U64` / `Addr` / `Ptr A` を使う
- `layout` でサイズ、アラインメント、フィールドオフセットを持つruntime-backed型を書く
- `static-bytes` / `static-cell` / `static-value` でrodata、bss、section-backed objectを書く。`static-bytes` では明示的な `(u8 n)` 列に加えて、狭いbyte string literalも使える
- 現在のS式source subsetを `fmt` / `fmt --check` / `fmt --write` でcanonicalに扱う
- `lint` と `diagnostics --json` でcanonical formatting、source bundle parsing、checker diagnosticsをテキストまたは `silt.diagnostics.v0` JSONとして確認し、`silt lsp` のdiagnostics-only stdio seedでopen/change/closeされた単一document textへformatter/parser/checker diagnosticsを `textDocument/publishDiagnostics` として出す
- `editors/neovim/` の軽量filetype/syntax fileで現在のsurfaceを編集する
- package command spineとして、`silt new NAME` で単純なbin/test scaffoldを生成し、単一local packageの `Silt.pkg` からno-argument hosted entry functionを `build` / `run` / `test` し、`silt doc` でmanifest由来のHTML package docsを生成し、`run -- ARG...` でhosted process argumentを渡し、名前を指定した単一のenvironment lookupを行い、bin entryの結果をprocess statusとして外に返し、明示的な `TextView` path/bodyでfirst-orderなhosted file writeを行い、明示的な `TextView` pathからhost-ownedな `TextView` へfirst-orderなhosted file readを行い、`HostReadFileResult` でfile body/statusをまとめ、host-ownedな `TextView` へstdin全体を読む狭いhosted stdin readを行い、stderr diagnosticsを明示的なbyte/text writerで出し、`hosted-copy` でfile read result、file write、stderr diagnostics、process statusを一つの実行経路として組み合わせ、`hosted-size-report` でprocess args、first-order file read result layout、ASCII decimal parse/format、file write、stdout、stderr diagnostics、process statusを一つの実行経路として組み合わせ、`hosted-config-report` で複数file read、first-byte split、ASCII whitespace trim、static key compare、ASCII decimal parse/format、file write、stdout、stderr diagnostics、process statusを一つの実行経路として組み合わせ、`hosted-lf-count` でfile read、literal LF byte count、ASCII decimal format、file write、stdout、stderr diagnostics、process statusを一つの実行経路として組み合わせ、`hosted-stdin-lf-count` でstdin read、literal LF byte count、ASCII decimal format、stdout、stderr diagnostics、process statusを一つの実行経路として組み合わせ、`hosted-byte-search` でone-byte argument validation、file read、explicit `TextView` 上のbyte containment search、stdout/statusによるfound/missing reporting、stderr diagnosticsを一つの実行経路として組み合わせ、`hosted-text-search` でnon-empty needle validation、file read、explicit `TextView` 上のbyte/text substring containment search、stdout/statusによるfound/missing reporting、stderr diagnosticsを一つの実行経路として組み合わせ、`text-eq-test`、`text-prefix-test`、`text-suffix-test`、`text-scan-test`、`text-search-test`、`text-line-test`、`text-count-test`、`ascii-test`、`ascii-slice-test`、`ascii-trim-test`、`ascii-decimal-u64-test`、`ascii-decimal-u64-format-test`、`list-recursion-test` でbyte-backed text predicate、ASCII predicate、ASCII trim、ASCII decimal parse/format、closed List recursionをpackage testとして確認する
- `hosted-byte-drop` でstdin read、one-byte argument validation、byte equality、retained-byte stdout output、stderr diagnostics、process statusを一つの実行経路として組み合わせる
- `hosted-source-hygiene` でfile read、explicit `TextView` 上のNUL/CR byte-containment checks、stdout/status reporting、stderr diagnostics、process statusを一つの実行経路として組み合わせる
- `hosted-ascii-trim` でfile read、explicit `TextView` 上のallocation-free ASCII whitespace trim、file write、stdout、stderr diagnostics、process statusを一つの実行経路として組み合わせる
- 標準ライブラリseedとして、checker/normalizer-backedな `Option` / `Result` とmap/and-then系combinator、built-in checker/normalizer-backed `List` に対するoption-shaped head/tail accessor、closed `List` structural recursionのための `list-elim` / `list-length` / `list-map` / `list-filter` / `list-any` / `list-all` / `list-find` / `list-count` / `list-append` / `list-reverse` / `list-fold-right`、`nat-elim` による純粋な `Nat` addition/multiplication、predecessor、saturating subtraction、equality/order helper、`U8` / `Ptr U8` 上の `ByteSlice` / `TextView`、boundedなempty/take/drop view helper、`byte-slice-eq` / `text-eq` によるbyte-wise equality、`byte-slice-starts-with` / `text-starts-with` によるprefix check、`byte-slice-ends-with` / `text-ends-with` によるsuffix check、first-byte find/contains/split helper、狭いbyte/text substring find/contains helper、LF-oriented first-line split helper、single-byte count helper、`U8` 上のASCII byte predicate、explicitな `ByteSlice` / `TextView` 上の狭いall-ASCII class check、allocationなしの狭いASCII whitespace trim view、空入力、非数字、overflowを拒否する狭いASCII decimal `U64` parser、caller-providedな `AsciiDecimalU64Buffer` にASCII decimal `U64` を書いて明示的な `TextView` として返すformatter、`Nat` / `U64` の明示bridge、`nat-elim` からC loopへ落ちるfirst-orderなhosted text output境界、明示的なhosted argument境界と `host-arg-text`、明示的なhosted environment境界と `host-env-text`、明示的なhosted file-write境界と `host-write-file`、明示的なhosted file-read境界と `host-read-file`、狭いread-status観測、first-orderな `HostReadFileResult` wrapper、明示的なhosted stdin read境界と `host-read-stdin`、first-orderな `HostReadStdinResult` wrapper、stderr byte/text writer、小さなdiagnostic/status helper、caller-provided bufferを使うhosted ASCII decimal output helperを使う

これらはSiltの型検査、正規化、layout検査、数量チェックによって支えられます。たとえば、`Ptr U64` と `Ptr BootInfo` は同じ機械表現になり得ますが、Siltの型では区別されます。`layout` のフィールドは、宣言したサイズ、アラインメント、オフセットに従って扱われます。

ここで得られるのは、言語内の一貫性です。値の形、型の境界、数量、effect stateが、Siltの中で食い違わないことを確認します。

## 生成物で確認されること

- freestanding Cを生成する
- x86_64 ELF/Limine artifactを検証する
- QEMUでSilt由来のserial/debug-exit動作を観測する
- Limine HHDM/Memmapの最小responseを読み、allocator handoffまで到達する

これらは、生成C、object symbol、section、linker output、target contract、boot contract、QEMU smokeによって確認します。低レイヤーでは、型だけでは十分ではありません。シンボル名、セクション、エントリ番地、ブートプロトコルの配置がずれると、プログラムは起動しません。

ここで得られるのは、外部世界との接続です。Siltの中で正しい値が、C compiler、linker、bootloader、QEMUからも期待した形で見えることを確認します。

## 保証しないこと

- マクロ
- module/import system
- package ecosystem、dependency resolution、workspace、lockfile、package publishing、package resolution、selectable package template
- 現在のdiagnostics-only stdio seedを超える成熟したLSP/editor tooling、semantic highlighting、hover、completion、workspace-wide analysis、LSP側source-bundle/include展開、formatter-on-save連携、editor package-manager plugin
- source comment extraction、type-signature docs、cross-package docs
- append mode、directory operation、path library、in-place file editing、現在のsuccess/failure statusを超える詳細なfile-read error分類、allocator-backed Silt file buffer、streaming stdin、独立した寿命を持つrepeated stdin read、`tr`-style byte translation、process spawning、signal、現在の明示的なbyte/text writerを超えるstdout/stderr abstraction、general hosted IO、environment enumeration/mutation、multi-entry config format、generic CLI/config parser、multi-file source traversal、`silt new NAME` / `silt run [TARGET] -- ARG...` / `silt test TARGET` / `silt doc` を超えるpackage argument policy
- Unicode category、locale-sensitive behavior、case conversion
- UTF-8 validation、`static-bytes` のbyte literal convenienceを超えるgeneral string literal/string type、CRLF normalization、split-all line API、literal LF byte countを超えるline semantics、汎用文字列、配列、dynamic slice、allocator-backed byte/text buffer、regexやUnicode-aware search tool、現在のsingle-byte find/contains/split/count helper、狭いbyte/text substring find/contains helper、LF-oriented first-line split helper、狭いall-ASCII class check、狭いASCII whitespace trim、ASCII decimal `U64` parser、ASCII decimal `U64` formatterを超えるsubstring/search/general scanning API、collation、text-normalization API
- 符号、基数prefix、separator、狭いASCII view helperを超えるwhitespace trimming、詳細なparse error分類、符号付きformat、radix format、padding、alignment、locale formatting、generic decimal output abstraction、parser/formatter combinator library
- indexed inductive families
- 完全なtotality checking
- 任意のuser-defined dataに対するstructural recursion、dependent list induction
- generic ADTのruntime representation、open-term `List` algebraic laws、broad sequence library
- general closure conversion
- 完全なmemory map parser
- mutating free-list allocator
- multi-frame allocation
- 直接object/binary emission
- self-hosting
- kernel全体の形式証明

この一覧は、Siltを弱く見せるためのものではありません。低レイヤー言語では、保証しないことを明確にすることが重要です。allocator handoffの例は、allocatorに渡す事実を型付きに組み立てる例であって、汎用allocatorの完成を意味しません。Limineの最小responseを読むことは、完全なmemory map parserを意味しません。

Siltの基本姿勢は、主張をchecker、正規化、生成物、実行観測のいずれかに結びつけることです。読者がSiltコードを読むときも、同じ姿勢で見ると理解しやすくなります。型が保証していること、backendが保存していること、QEMU smokeが観測していることを分けて読んでください。

この本で身につけてほしいのは、Siltの構文を暗記することだけではありません。低レイヤーの主張を、どの層で支えているかを読む力です。その読み方ができれば、Siltの現在地も、次に強めるべき場所も、自分で判断できるようになります。
