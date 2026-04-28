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
- `static-bytes` / `static-cell` / `static-value` でrodata、bss、section-backed objectを書く

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
- indexed inductive families
- 完全なtotality checking
- 汎用文字列、配列、dynamic slice
- 完全なmemory map parser
- mutating free-list allocator
- multi-frame allocation
- 直接object/binary emission
- self-hosting
- kernel全体の形式証明

この一覧は、Siltを弱く見せるためのものではありません。低レイヤー言語では、保証しないことを明確にすることが重要です。allocator handoffの例は、allocatorに渡す事実を型付きに組み立てる例であって、汎用allocatorの完成を意味しません。Limineの最小responseを読むことは、完全なmemory map parserを意味しません。

Siltの基本姿勢は、主張をchecker、正規化、生成物、実行観測のいずれかに結びつけることです。読者がSiltコードを読むときも、同じ姿勢で見ると理解しやすくなります。型が保証していること、backendが保存していること、QEMU smokeが観測していることを分けて読んでください。

この本で身につけてほしいのは、Siltの構文を暗記することだけではありません。低レイヤーの主張を、どの層で支えているかを読む力です。その読み方ができれば、Siltの現在地も、次に強めるべき場所も、自分で判断できるようになります。
