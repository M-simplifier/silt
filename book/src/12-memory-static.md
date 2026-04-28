# 12. `load`、`store`、静的オブジェクト

Siltには、capability-indexedな `load` と `store` があります。

メモリ操作は、低レイヤーで最も強力で、最も壊れやすい操作です。Siltでは、読み書きをただのポインタ操作にせず、どの状態で行うかを型に載せます。

```lisp
(load SerialReady BootInfo limine-boot-info)
(store SerialReady SerialReady BootInfo limine-boot-info value)
```

`load` は、指定したcapability stateの中でポインタから値を読みます。`store` は、pre/post stateを明示して値を書きます。

静的な保存場所は `static-cell` で作ります。

```lisp
(static-cell limine-boot-info BootInfo)
```

これは `limine-boot-info : Ptr BootInfo` を合成し、C backendでは `.bss.silt` にゼロ初期化領域を生成します。

読み書きの典型形はこうです。

```lisp
(bind SerialReady SerialReady SerialReady Unit Unit
  (store SerialReady SerialReady BootInfo limine-boot-info info)
  (fn ((stored 1 Unit))
    (let ((ignored-stored 0 stored))
      (bind SerialReady SerialReady SerialReady BootInfo Unit
        (load SerialReady BootInfo limine-boot-info)
        (fn ((loaded 1 BootInfo))
          next)))))
```

長いですが、意味は明確です。

1. `info` を `limine-boot-info` にstoreする
2. storeの結果 `Unit` を受け取る
3. その結果値自体は使わない
4. 同じセルから `BootInfo` をloadする
5. loadした値を後続で検査する

読み取り専用の静的バイト列には `static-bytes` を使います。

```lisp
(static-bytes limine-ok-bytes
  ((u8 83) (u8 73) (u8 76) (u8 84)))
```

これは `Ptr U8` と長さ `U64` を合成し、C backendでは `.rodata.silt` の `static const uint8_t` に落ちます。

コンパイル時に初期値を持つ静的layoutには `static-value` を使います。

```lisp
(static-value limine-base-revision
  LimineBaseRevision
  .limine_requests
  limine-base-revision-value)
```

これはLimine requestのように、ブートローダが見る必要のあるセクション配置に使います。

Siltの静的オブジェクト機能は、一般的なグローバルオブジェクトシステムではありません。低レイヤー検証に必要な小さな橋として使います。

この章の大事な点は、静的領域を「どこかにあるグローバル」として扱わないことです。`static-cell` は型付きポインタを合成し、backendでは具体的なセクションのバイト列になります。Siltは、その両方を同じプログラムから追えるようにします。
