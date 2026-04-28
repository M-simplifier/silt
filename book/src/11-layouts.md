# 11. `layout`: メモリ表現を型にする

Siltの `layout` は、低レイヤー表現の中心です。

普通のレコード型は、「どんなフィールドを持つか」を表します。Siltの `layout` はそこに加えて、「メモリ上でどこに置かれるか」まで表します。

```lisp
(layout BootInfo 40 8
  ((hhdm-offset U64 0)
   (memmap-count U64 8)
   (first-base U64 16)
   (first-length U64 24)
   (first-kind U64 32)))
```

これは、`BootInfo` が40バイト、8バイトアラインメントのruntime-backed型であることを宣言します。各フィールドは、型とオフセットを持ちます。

この宣言を読むときは、フィールド名だけを見ないでください。`first-base` が `U64` で、オフセット16にある。この三つがそろって一つの事実です。

Siltはlayout宣言を検査します。

- アラインメントは正の2冪である
- サイズはアラインメントの倍数である
- フィールドは型のアラインメントを満たす
- フィールドはlayoutの範囲内に収まる
- フィールド同士が重ならない

値は `layout-values` で作れます。

```lisp
(layout-values BootInfo
  hhdm-offset
  memmap-count
  first-base
  first-length
  first-kind)
```

これは宣言順にフィールドを埋めます。フィールド名で書く `layout` literalもありますが、長い低レイヤー構造では `layout-values` が便利です。

フィールドを読むには `field` を使います。

```lisp
(field BootInfo first-base info)
```

`let-layout` を使うと、複数フィールドを一度に束縛できます。

```lisp
(let-layout BootInfo
  ((hhdm-offset hhdm)
   (first-base base)
   (first-length length))
  info
  body)
```

低レイヤーでは、layoutは単なるデータ構造ではありません。ABI、ブートプロトコル、静的storage、C backendの出力にそのまま影響します。

たとえば `KernelAllocatorHandoff` は96バイトのlayoutです。

```lisp
(layout KernelAllocatorHandoff 96 8
  ((allocator-ready U64 0)
   (semantics-ready U64 8)
   ...
   (handoff-ready U64 88)))
```

このlayoutは、C backendで対応するC struct風の表現と、`.bss.silt` の静的セルに落ちます。Siltでは「この値はどんなフィールドを持つか」だけでなく、「この値はメモリ上でどのように見えるか」を型宣言に含めます。

`layout` を読む力は、Siltで低レイヤーを書く力そのものです。サイズ、アラインメント、オフセットは、コメントではなくプログラムの一部です。
