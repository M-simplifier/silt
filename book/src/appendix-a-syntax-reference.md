# Appendix A: 構文リファレンス

この付録は、各章で使った主要構文の早見表です。意味を学ぶための章ではなく、読んでいる途中で形を確認するために使ってください。

## トップレベル

```lisp
(claim name type)
(def name expr)
(data Name ((A 0 Type)) (Ctor) (Ctor2 A))
(layout Name size align ((field Type offset) ...))
(static-bytes name ((u8 n) ...))
(static-cell name Type)
(static-value name Type .section value)
(extern name type c_symbol)
(export name c_symbol)
(section name .section-name)
(calling-convention name sysv-abi)
(entry name)
(abi-contract name (...))
(target-contract target (...))
(boot-contract name (...))
(include file.silt)
```

## 基本式

```lisp
Type
Bool
True
False
Nat
Z
(S n)
(u8 42)
(u64 4096)
(addr 1048576)
(Ptr U64)
```

## 関数

```lisp
(Pi ((x A) (y B)) R)
(fn ((x A) (y B)) body)
(f x y)
```

## 数量

```lisp
(Pi ((A 0 Type) (x 1 A) (y A)) A)
```

省略時は `omega` です。

## 分岐

```lisp
(match b
  ((True) t)
  ((False) f))
```

## layout

```lisp
(layout Header 16 8
  ((magic U64 0)
   (next Addr 8)))

(layout-values Header (u64 1) (addr 0))
(field Header magic header)
(let-layout Header ((magic m) (next n)) header body)
```

## memory

```lisp
(load Heap U64 ptr)
(store Heap Heap U64 ptr value)
(load-field Heap Header magic ptr)
(store-field Heap Heap Header magic ptr value)
```

## effect

```lisp
(Eff pre post A)
(Eff Heap A)
(pure Heap A value)
(bind pre mid post A B action continuation)
```

## x86 I/O

```lisp
(x86-out8 pre post port value)
(x86-in8 state port)
```

このリファレンスは完全な仕様ではありません。各フォームの文脈は、この本の対応する章と `examples/` の実例を参照してください。Siltでは、構文の形だけでなく、その構文がどの層の境界を表しているかが重要です。
