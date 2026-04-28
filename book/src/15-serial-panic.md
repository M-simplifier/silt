# 15. シリアルI/Oとpanic

この本のQEMU smokeは、シリアル出力とdebug-exitで観測します。

低レイヤーの最初の成功は、派手な画面ではありません。決めたバイト列がシリアルに出ること、決めた終了コードでQEMUから戻ることです。Siltは、その小さな観測を型付きの手続きとして組み立てます。

COM1のベースポートは `1016`、つまり `0x3f8` です。Siltでは次のように書きます。

```lisp
(def serial-out
  (fn ((pre 0 Type)
       (post 0 Type)
       (offset U64)
       (value U64))
    (x86-out8 pre post (u64-add (u64 1016) offset) value)))
```

送信前にはline statusを読みます。

```lisp
(claim serial-line-status (Eff SerialReady SerialReady U64))
(def serial-line-status
  (x86-in8 SerialReady (u64-add (u64 1016) (u64 5))))
```

送信可能かどうかはbit 5で判定します。

```lisp
(def serial-ready
  (fn ((status U64))
    (u64-eq (u64-and status (u64 32)) (u64 32))))
```

1バイト書く関数は、読み取りと条件分岐をeffectでつなぎます。

```lisp
(def serial-write-byte
  (fn ((value U64))
    (bind SerialReady SerialReady SerialReady U64 Unit serial-line-status
      (fn ((status 1 U64))
        (match (serial-ready status)
          ((True) (serial-out SerialReady SerialReady (u64 0) value))
          ((False) (pure SerialReady Unit tt)))))))
```

panic経路も同じserial/debug-exit surfaceを使います。ただし、post-stateが異なります。

```lisp
(data PanicCause ()
  (PanicSmoke)
  (PanicOom)
  (PanicInvariant))

(data KernelPanicked ((cause 0 PanicCause)) ())
```

panic entryは `KernelPanicked PanicSmoke` に到達します。OOM用、invariant用のpanic関数は、それぞれ `KernelPanicked PanicOom` と `KernelPanicked PanicInvariant` に到達します。

これは完全なpanic runtimeではありません。stack unwind、halt loop、interrupt-safe panic処理はありません。しかし、Siltが異なるpanic causeを型のpost-stateで区別でき、QEMU上でpanic markerとdebug-exitを観測できることを示しています。

ここで大切なのは、panicを「失敗したら何かを出す処理」としてだけ読まないことです。どのcauseで止まったのかが型に現れ、外部観測でもmarkerとして見える。この二重の読み方が、Siltらしい低レイヤーの小さな保証です。
