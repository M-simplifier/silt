# 16. ブート情報からカーネル情報へ

Limine responseを読んだだけでは、カーネルが使いやすい情報にはなっていません。Siltでは、選んだbootloader factsを `BootInfo` に詰めます。

この章の主題は、外から受け取った事実を、そのまま信用範囲の広い値にしないことです。まず小さなhandoffに詰め、保存し、読み直し、predicateで確認します。

```lisp
(layout BootInfo 40 8
  ((hhdm-offset U64 0)
   (memmap-count U64 8)
   (first-base U64 16)
   (first-length U64 24)
   (first-kind U64 32)))
```

ここで扱うのは、Memmapの最初のentryだけです。完全なmemory map parserではありません。

`limine-boot-info-from-entry` は、Memmap entryから必要な値を取り出します。

```lisp
(let-layout LimineMemmapEntry
  ((base first-base)
   (length first-length)
   (kind first-kind))
  entry
  ...)
```

`first-length` が0なら何もしません。非ゼロなら `BootInfo` として保存します。

```lisp
(limine-boot-info-store-and-report
  hhdm-offset
  memmap-count
  first-base
  first-length
  first-kind)
```

保存先は `static-cell` です。

```lisp
(static-cell limine-boot-info BootInfo)
```

この後、Siltは `BootInfo` からカーネル向けの `KernelBootSpan` を作ります。

```lisp
(layout KernelBootSpan 40 8
  ((physical-base U64 0)
   (physical-end U64 8)
   (direct-base U64 16)
   (direct-end U64 24)
   (kind U64 32)))
```

HHDM offsetを足すことで、物理アドレスに対応するdirect map addressを得ます。

この章のポイントは、外部プロトコルから受け取った事実を、そのまま無制限に信じないことです。Siltは、読み取った値を小さな型付きhandoffへ詰め、保存し、読み直し、predicateで確認し、QEMU markerで観測します。

低レイヤーの第一歩は、情報を増やすことではなく、受け取った情報の境界を明確にすることです。

この考え方は、次のフレーム候補の章でさらに重要になります。boot情報からすぐに「使えるメモリ」を作るのではなく、候補、適格性、予約意図、状態へと段階を分けます。
