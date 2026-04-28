# 4. 型、`claim`、`def`

Siltでは、トップレベル定義は基本的に二段階です。

```lisp
(claim name TypeOfName)
(def name expression)
```

`claim` は契約です。`def` はその契約を満たす実装です。

この分離は、単なる構文上の都合ではありません。読む人にとっては、先に約束が見えます。コンパイラにとっては、実装をどの型で検査するかが明示されます。

たとえば、`U64` の値を定義します。

```lisp
(claim page-size U64)
(def page-size (u64 4096))
```

関数は `Pi` と `fn` で書きます。

```lisp
(claim add-page
  (Pi ((base U64)) U64))
(def add-page
  (fn ((base U64))
    (u64-add base (u64 4096))))
```

`Pi` は関数型です。依存型言語では、戻り値の型が前の引数に依存できます。Siltの構文とコアも、この方向を向いています。

型そのものは `Type` に属します。

```lisp
(claim Bool-is-type Type)
(def Bool-is-type Bool)
```

このような「型を値のように扱う」感覚は、低レイヤーだけを見ていると奇妙に見えるかもしれません。しかし、Siltでは低レイヤー表現も型で制御します。だから、型が計算対象になることは重要です。

たとえば、`Ptr U64` と `Ptr BootInfo` が同じ機械表現を持つとしても、Siltでは同じ型ではありません。その区別を最後まで残すために、型は表面上の飾りではなく、プログラムを読む中心になります。

低レイヤーでも同じです。

```lisp
(claim serial-line-status
  (Eff SerialReady SerialReady U64))
(def serial-line-status
  (x86-in8 SerialReady (u64-add (u64 1016) (u64 5))))
```

この宣言だけで、次のことがわかります。

- シリアル初期化済み状態で実行する
- 実行後もシリアル初期化済み状態である
- 結果として `U64` を返す
- 実装はx86のI/Oポート読み取りである

Siltでは型は単なる注釈ではなく、低レイヤーの操作境界を読むための第一情報です。実装の前に型を見る、という習慣がここから始まります。
