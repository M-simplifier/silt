# 17. フレーム候補、予約、free-list seed

`KernelBootSpan` からすぐallocatorへ行くのは危険です。Siltでは、段階を細かく分けています。

この章は、名前を慎重に使う練習です。candidateは候補であって、所有ではありません。intentは意図であって、状態変化ではありません。seedは足場であって、汎用free listではありません。

まず、frame candidateを作ります。

```lisp
(layout KernelFrameCandidate 40 8
  ((physical-base U64 0)
   (direct-base U64 8)
   (page-count U64 16)
   (kind U64 24)
   (ready U64 32)))
```

これは「使ってよいフレーム」ではありません。候補です。

次にeligibilityを作ります。

```lisp
(layout KernelFrameEligibility 48 8
  ((candidate-ready U64 0)
   (usable-kind U64 8)
   (physical-page-aligned U64 16)
   (direct-page-aligned U64 24)
   (nonzero-pages U64 32)
   (eligible U64 40)))
```

ここで初めて、Limineのkind、ページアラインメント、非ゼロページ数を見ます。

さらにreservation intentを作ります。

```lisp
(layout KernelFrameReservationIntent 56 8
  ((physical-base U64 0)
   (direct-base U64 8)
   (page-count U64 16)
   (candidate-ready U64 24)
   (eligible U64 32)
   (requested U64 40)
   (intent-ready U64 48)))
```

intentは状態変化ではありません。「予約したい」という意思決定の形です。

その後、reservation invariantとreservation stateを作ります。

```lisp
(layout KernelFrameReservationState 64 8
  ((physical-base U64 0)
   (direct-base U64 8)
   (page-count U64 16)
   (previous-reserved U64 24)
   (reserved U64 32)
   ...
   (state-ready U64 56)))
```

最後に、free-list seedを作ります。

```lisp
(layout KernelFrameFreeListSeed 64 8
  ((reserved-base U64 0)
   (free-base U64 8)
   (free-direct-base U64 16)
   (reserved-count U64 24)
   (free-count U64 32)
   ...
   (seed-ready U64 56)))
```

これは汎用free listではありません。一つの予約済みフレームと、一つの次候補/countを記録するseedです。

Siltの強みは、このような名詞を簡単に増やすことではなく、それぞれの名詞にlayout、pure constructor、ready predicate、static storage roundtrip、QEMU markerを要求していることです。名前だけの抽象を、低レイヤー実装の事実へ結びつけています。

この章を読むときは、慎重すぎるように感じるかもしれません。しかし、低レイヤーでは「候補」を「所有」と呼んだ瞬間に、次の設計が歪みます。Siltは、その言葉のずれを型付きの段階に分けて残します。
