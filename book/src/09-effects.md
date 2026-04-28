# 9. Effect stateで副作用を制御する

Siltでは、副作用を `Eff` で表します。

ここでの発想は単純です。副作用を「どこでも起こせるもの」にしない。どの状態から始まり、どの状態で終わるかを型に書く。

```lisp
(Eff pre post A)
```

これは「状態 `pre` から `post` へ進み、`A` 型の値を返す操作」と読みます。

何も状態を変えない場合は、次の短縮形も使えます。

```lisp
(Eff Heap U64)
```

これは `Eff Heap Heap U64` と同じ意味です。

effectの値を返すには `pure` を使います。

```lisp
(pure SerialReady Unit tt)
```

effectをつなぐには `bind` を使います。

```lisp
(bind SerialReady SerialReady SerialReady U64 Unit
  serial-line-status
  (fn ((status 1 U64))
    ...))
```

この例では、`serial-line-status` が `U64` を返し、その結果を `status` として後続に渡します。pre/mid/postがすべて `SerialReady` なので、シリアル状態を保ったまま読む操作です。

状態を変える例は、シリアル初期化です。

```lisp
(claim serial-init (Eff BootIO SerialReady Unit))
```

これは、ブート直後の `BootIO` 状態から、シリアルを使える `SerialReady` 状態へ進む操作です。

QEMU debug-exitはさらに一般的です。

```lisp
(claim qemu-debug-exit
  (Pi ((pre 0 Type)
       (post 0 Type)
       (code U64))
      (Eff pre post Unit)))
```

成功エントリでは、最後に `KernelDone` へ進みます。

```lisp
(qemu-debug-exit SerialReady KernelDone (u64 16))
```

panicエントリでは、別のpost-stateへ進みます。

```lisp
(qemu-debug-exit SerialReady (KernelPanicked PanicSmoke) (u64 32))
```

この設計の意味は、低レイヤー副作用を「どこでも実行できる命令」として扱わないことです。どの状態で許され、実行後にどの状態になるかを型に置きます。

Siltでは、低レイヤー手続きの順序を単なる実行順ではなく、型に現れる状態遷移として扱います。

この章を読み終えたら、`Eff pre post A` を「副作用つきのA」ではなく、「preからpostへ進む手続き」と読んでください。その読み方が、シリアルI/O、panic、QEMU debug-exit、メモリ操作の章でそのまま使われます。
