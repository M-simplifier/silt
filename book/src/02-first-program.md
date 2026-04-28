# 2. 最初のSiltプログラム

この章では、Siltを実際に動かします。

最初に見るのは恒等関数です。何もしない関数に見えますが、Siltではこの小さな定義から、型引数、数量、`claim` と `def` の関係を読み取れます。

```lisp
(claim id (Pi ((A 0 Type) (x A)) A))
(def id
  (fn ((A 0 Type) (x A)) x))
```

これをチェックするには、リポジトリルートから次を実行します。

```bash
cabal run silt -- check examples/identity.silt
```

Siltのトップレベルは、基本的に宣言の列です。`claim` で型を宣言し、`def` で本体を与えます。原則として、トップレベル定義には先に `claim` が必要です。

これは不便さではありますが、重要な利点があります。型推論に頼りすぎず、プログラムの境界を明示できるからです。Siltでは、実装を見る前に、その名前が何を約束しているかを読めます。

正規化を見るには `norm` を使います。

```bash
cabal run silt -- norm examples/stage1.silt three
```

`norm` は、定義を正規形まで評価して表示します。依存型言語では、プログラムの実行と型レベルの計算が近い関係を持ちます。Siltも、型検査の中で正規化を使います。

最初のうちは、`check` と `norm` の二つを往復すると理解が崩れにくくなります。`check` は「この定義が約束を満たすか」を見ます。`norm` は「この定義がどんな値まで計算されるか」を見ます。

Siltのコードには、普通の関数型言語のような部分もあります。

```lisp
(claim choose
  (Pi ((A 0 Type) (cond Bool) (x A) (y A)) A))
(def choose
  (fn ((A 0 Type) (cond Bool) (x A) (y A))
    (match cond
      ((True) x)
      ((False) y))))
```

ここで `A` は erased な型引数です。実行時には必要ないため、数量 `0` が付いています。`cond`、`x`、`y` は実際に使う値です。

一方で、Siltは低レイヤーのコードも同じS式で書きます。

```lisp
(claim read-status (Eff SerialReady SerialReady U64))
(def read-status
  (x86-in8 SerialReady (u64 1021)))
```

ここでは、I/Oポート `1021` から1バイト読みます。読み取りは副作用ですが、`Eff SerialReady SerialReady U64` によって「SerialReady状態を保ったまま `U64` を返す操作」として表現されます。

Siltを読む最初のコツは、`claim` を先に読むことです。`def` は実装ですが、`claim` はそのコードが何を約束しているかを示します。低レイヤーの章に進んでも、この順番は変わりません。
