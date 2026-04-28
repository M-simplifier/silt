# 8. 正規化と等しさ

依存型言語では、型検査のために計算が必要になります。Siltも、定義上の等しさを判断するために正規化を使います。

正規化は、難しい内部機構としてだけ見る必要はありません。最初は「Siltが、ある定義をどこまで具体的な値として読めるかを見る道具」と考えるとよいです。

コマンドラインでは `norm` で正規形を見られます。

```bash
cabal run silt -- norm examples/stage1.silt three
```

`Nat` のような小さな例では、正規化結果は直感的です。

```lisp
(S (S (S Z)))
```

低レイヤー例でも、正規化は重要です。

```bash
cabal run silt -- norm examples/limine.silt kernel-allocator-handoff-sample-ready
```

この結果は次のようになります。

```text
True
```

つまり、サンプルのallocator handoffが、Silt内のpure predicateによってreadyと判定されることを確認できます。

さらに、handoff値そのものも正規化できます。

```bash
cabal run silt -- norm examples/limine.silt kernel-allocator-handoff-sample
```

結果は、`KernelAllocatorHandoff` のフィールドがすべて具体的な `u64` 値に落ちた形になります。たとえば `physical-base` は `4096`、`direct-base` は `8192`、`handoff-ready` は `1` です。

Siltの型検査器は、内部でNbE、normalization by evaluationを使います。これは、項を評価して値にし、必要なときに正規形へquote backする方法です。構文をただ書き換えるだけよりも、依存型コアの等しさを扱いやすくなります。

Siltの正規化が扱う範囲は限定されています。全機能の完全な計算体系があるわけではありません。しかし、`Bool`、`Nat`、`U64`演算、layout値、field projection、effectの一部の簡約など、実装済み範囲では検証の中心として使われています。

Siltを書くとき、`norm` は単なるデバッグ用コマンドではありません。型付き低レイヤー値が期待どおりの証拠形になっているかを確認する道具です。

低レイヤーでは、抽象的な名前だけでは足りません。`KernelAllocatorHandoff` のような値が、実際に具体的なフィールド値まで落ちることを確認できるから、次の層へ進めます。
