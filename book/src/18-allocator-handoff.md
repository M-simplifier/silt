# 18. allocator handoff

この章では、ここまでに扱った低レイヤー機能を使って、allocator handoffを一つの総合例として読みます。

目標は、汎用allocatorを完成させることではありません。bootloaderから読んだ事実、frame candidate、reservation、free-list seed、alloc/free traceを、allocatorへ渡せる形の型付きhandoffへまとめることです。

Siltは、`KernelFrameFreeListSeed` から一つのalloc/free traceを作ります。

```lisp
(layout KernelFrameAllocOneState 64 8
  ((allocated-base U64 0)
   (allocated-direct-base U64 8)
   (reserved-count-before U64 16)
   (free-count-before U64 24)
   (reserved-count-after U64 32)
   (free-count-after U64 40)
   (allocated-count U64 48)
   (alloc-ready U64 56)))
```

対応するfree側もあります。

```lisp
(layout KernelFrameFreeOneState 64 8
  ((freed-base U64 0)
   (freed-direct-base U64 8)
   ...
   (released-count U64 48)
   (free-ready U64 56)))
```

次に、このtraceを `KernelFrameAllocatorState` にまとめます。

```lisp
(layout KernelFrameAllocatorState 104 8
  ((initial-reserved-count U64 0)
   (initial-free-count U64 8)
   (allocated-base U64 16)
   ...
   (allocator-ready U64 96)))
```

ここからAPI-shaped resultを作ります。

ここで「API-shaped」と呼んでいるのは、実際のallocator APIがすべて揃ったという意味ではありません。今後のAPIが返すべき形を、小さな結果recordとして先に切り出しているという意味です。

```lisp
(def kernel-frame-allocator-alloc-one
  (fn ((state KernelFrameAllocatorState))
    (layout-values KernelFrameAllocatorAllocResult
      ...
      (kernel-bool-word (kernel-frame-allocator-state-ready state)))))
```

さらにsemantics witnessを作ります。

```lisp
(def kernel-frame-allocator-semantics-state-from-api
  (fn ((alloc KernelFrameAllocatorAllocResult)
       (free KernelFrameAllocatorFreeResult))
    (layout-values KernelFrameAllocatorSemanticsState
      ...
      (kernel-frame-allocator-semantics-ready-word alloc free))))
```

このsemanticsは、OOMを証明するものではありません。この例ではfree frameがある前提で、alloc progressとfree後のreuse candidateを確認します。

leaseは、allocされたフレームとfreeされたフレームが同じであることを記録します。

```lisp
(def kernel-frame-lease-from-api
  (fn ((alloc KernelFrameAllocatorAllocResult)
       (free KernelFrameAllocatorFreeResult))
    (layout-values KernelFrameLease
      (field KernelFrameAllocatorAllocResult allocated-base alloc)
      ...
      (kernel-frame-lease-ready-word alloc free))))
```

最後が `KernelAllocatorHandoff` です。

実行時の外部観測では、この到達点を `SILT_ALLOC_HANDOFF` markerとして確認します。Siltの内部では、markerそのものではなく、handoffを構成する型付き値とready predicateが本体です。

```lisp
(def kernel-allocator-handoff-from-api
  (fn ((state KernelFrameAllocatorState)
       (alloc KernelFrameAllocatorAllocResult)
       (free KernelFrameAllocatorFreeResult))
    (layout-values KernelAllocatorHandoff
      (kernel-bool-word (kernel-frame-allocator-state-ready state))
      (kernel-frame-allocator-semantics-ready-word alloc free)
      (kernel-frame-lease-ready-word alloc free)
      ...
      (kernel-allocator-handoff-ready-word state alloc free))))
```

このhandoffは、Siltの低レイヤー記述を一つに束ねる例です。Limine boot factsから、型付きstorage、frame candidate、reservation、free-list seed、alloc/free trace、allocator state、API result、semantics、lease、handoffまで到達します。

ただし、これは汎用allocatorではありません。multi-frame allocation、mutating free list、完全なmemory map parsingを提供するものではありません。ここで示しているのは、allocatorに渡せる形の事実と小さな遷移を、Siltの型付き値として組み立てる方法です。

この章まで来ると、Siltの学び方はかなりはっきりします。低レイヤーの大きな名詞を、一度に信じない。候補、意図、状態、結果、意味、lease、handoffへ分ける。それぞれをlayoutにし、predicateで読み、storageを通し、実行物で観測する。Siltの魅力は、この分解を面倒な事務作業ではなく、言語の中心的な表現として扱うところにあります。
