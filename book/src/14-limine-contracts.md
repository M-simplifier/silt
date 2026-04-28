# 14. Limineブート契約

この本で扱うカーネル実行経路は、x86_64 + Limineです。Limineは、カーネルに入る前にブート情報を渡してくれるブートプロトコルです。

ここから先は、Siltの低レイヤー機能が一つのケーススタディとしてつながっていきます。layoutはブートプロトコルの構造になり、static-valueはrequest objectになり、effectはentryの実行順を支えます。

Silt側では、Limine requestを `layout` と `static-value` で定義します。

```lisp
(layout LimineHhdmRequest 48 8
  ((id0 U64 0)
   (id1 U64 8)
   (id2 U64 16)
   (id3 U64 24)
   (revision U64 32)
   (response (Ptr LimineHhdmResponse) 40)))
```

request objectは `.limine_requests` に置きます。

```lisp
(static-value limine-hhdm-request
  LimineHhdmRequest
  .limine_requests
  limine-hhdm-request-value)
```

このセクション配置はlinker scriptで保持され、検証scriptでも確認されます。

Siltのboot契約は次のように書きます。

```lisp
(boot-contract limine-x86_64
  ((protocol limine)
   (target x86_64-limine-elf)
   (entry limine-entry)
   (kernel-path /boot/silt-limine.elf)
   (config-path /boot/limine.conf)
   (freestanding)))
```

これは「このSilt entryはLimine x86_64 artifactとして使われる」という宣言です。checkerは、対応するtarget contractが存在するか、entryが一致するか、freestandingであるか、高位半分アドレスか、boot pathが妥当かを確認します。

Limine responseは、bootloaderがrequest object内の `response` pointerに書き込みます。Silt entryはそのpointerを読みます。

```lisp
(load SerialReady LimineHhdmRequest limine-hhdm-request)
```

続いて、layout fieldからresponse pointerを取り出します。

```lisp
(let-layout LimineHhdmRequest ((response response-ptr)) request ...)
```

nullでなければ、`response-ptr` から `LimineHhdmResponse` をロードします。

```lisp
(load SerialReady LimineHhdmResponse response-ptr)
```

ここで重要なのは、この章が完全なLimine parserを扱わないことです。扱うのは、HHDMとMemmapの最小response smokeです。広いrequest table parsingやframebuffer parsingは提供しません。

Siltの姿勢は、外部プロトコルを一気に全部包むことではありません。まず、小さなrequestとresponseを型付きに置き、実行物として観測できる経路を作ります。その小ささが、次章のシリアルI/Oとpanic経路を読みやすくします。
