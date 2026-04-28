# 3. S式、宣言、評価

Siltの表面構文はS式です。

最初に慣れるべきなのは、括弧の多さではありません。「先頭を見る」という読み方です。括弧で始まり、先頭のatomがフォーム名または関数名になります。

```lisp
(f x y z)
```

これは関数適用です。特別なフォームでなければ、リストはすべて適用として扱われます。

S式のよさは、見た目の珍しさではなく、構造がいつも同じ形で現れることです。宣言も、関数適用も、低レイヤーのlayoutも、まずは木として読めます。

トップレベルには、いくつかの宣言があります。

```lisp
(claim name type)
(def name expr)
(data Name ...)
(layout Name ...)
(static-cell name Type)
(static-value name Type section value)
(static-bytes name ((u8 83) ...))
(export name c_symbol)
(section name .text.silt.boot)
(calling-convention name sysv-abi)
(entry name)
```

SiltはLisp的な見た目を持ちますが、マクロ言語ではありません。S式は、homoiconicな設計へ進むための足場であり、いまは明示的で機械的に読める構文として機能しています。

この制限は、学習上はむしろ助けになります。まずは、構文拡張ではなく、宣言、型、評価、layoutの読み方に集中できます。

コメントは `;` から行末までです。

```lisp
; これはコメント
(claim answer U64)
(def answer (u64 42))
```

複数ファイルを扱う方法は二つあります。

一つはCLIで複数ファイルを順番に渡す方法です。

```bash
cabal run silt -- check examples/limine-serial.silt examples/limine.silt
```

もう一つは、Siltファイル内で `include` を使う方法です。

```lisp
(include limine-serial.silt)
(include limine-protocol.silt)
```

これはモジュールシステムではありません。名前空間、公開/非公開、別コンパイルを持つわけではなく、宣言列を順番に組み立てるための小さなinclude機能です。

評価は、単にプログラムを走らせるためだけではありません。型検査でも使われます。Siltのチェックでは、NbE、つまりnormalization by evaluationを使って、定義上等しい項を比較します。

たとえば `u64-add` のようなプリミティブ計算は正規化で簡約されます。

```bash
cabal run silt -- norm examples/lowlevel.silt aligned-page
```

Siltの読み方は、まず宣言を見る、次に型を見る、最後に本体を見る、という順が基本です。低レイヤーのコードでも同じです。S式は、その順番を邪魔しません。むしろ、どこを読めば境界が見えるかを揃えてくれます。
