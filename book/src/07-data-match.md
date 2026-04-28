# 7. データ型と`match`

Siltでは、代数的データ型を `data` で定義します。

データ型は、値の形を増やすだけの仕組みではありません。Siltでは、panic cause、kernel state、capabilityのような低レイヤーの区別を、ただのコメントではなく型として持つためにも使います。

```lisp
(data Option ((A 0 Type))
  (None)
  (Some A))
```

`A` は型引数なので数量 `0` です。`None` は値を持たないコンストラクタ、`Some` は `A` 型の値を一つ持つコンストラクタです。

値を分解するには `match` を使います。

```lisp
(claim unwrap-or
  (Pi ((A 0 Type) (fallback A) (x (Option A))) A))
(def unwrap-or
  (fn ((A 0 Type) (fallback A) (x (Option A)))
    (match x
      ((None) fallback)
      ((Some value) value))))
```

Siltの `match` は、builtinの `Bool` や `Nat` だけでなく、ユーザー定義データ型にも使えます。

```lisp
(match flag
  ((True) a)
  ((False) b))
```

Siltはindexed inductive familiesを提供していません。つまり、AgdaやIdrisのように、コンストラクタごとに結果型が精密に変わる完全な依存パターンマッチは扱いません。しかし、普通のparametric algebraic dataとpattern binder数量は動きます。

数量付きpattern binderは、リソース表現の入口になります。

```lisp
(match owned
  ((MkPair (spent 0) (fresh 1)) fresh))
```

ここでは、`spent` は使わず、`fresh` は一度だけ使います。低レイヤーの所有権やcapabilityを、まずユーザー定義データ型として試すための足場です。

Siltのデータ型は、標準ライブラリの豊富なコンテナを提供するためのものではありません。ここでの主役は、言語の意味を小さく保ったまま、所有権、capability、panic cause、kernel stateのような低レイヤー概念を型として持てるようにすることです。

この章の要点は、分岐そのものよりも「区別を型にする」ことです。低レイヤーのコードでは、区別が曖昧な値はすぐ危険になります。Siltでは、少なくともその区別をプログラムの表面に残そうとします。
