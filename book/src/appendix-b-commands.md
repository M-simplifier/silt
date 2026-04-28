# Appendix B: コマンドリファレンス

この付録は、本文で使った主要コマンドをまとめたものです。Siltを読むときは、`check`、`norm`、生成、検証を分けて使います。

## 型検査

```bash
cabal run silt -- check examples/identity.silt
cabal run silt -- check examples/limine.silt
```

## 正規化

```bash
cabal run silt -- norm examples/stage1.silt three
cabal run silt -- norm examples/limine.silt kernel-allocator-handoff-sample
cabal run silt -- norm examples/limine.silt kernel-allocator-handoff-sample-ready
```

## C生成

```bash
cabal run silt -- emit-c examples/stage1.silt add
cabal run silt -- emit-freestanding-c examples/limine.silt limine-entry
```

## contract確認

```bash
cabal run silt -- abi-contracts examples/freestanding.silt
cabal run silt -- target-contracts examples/limine.silt
cabal run silt -- boot-contracts examples/limine.silt
```

## backend検証

```bash
cabal test all
scripts/verify-stage0-backend.sh
scripts/verify-freestanding-backend.sh
scripts/verify-x86_64-elf-backend.sh
scripts/verify-limine-bridge.sh
```

## QEMU smoke

```bash
scripts/verify-limine-qemu-nix.sh
scripts/verify-limine-panic-qemu-nix.sh
```

`check` は型の約束を確認します。`norm` は値がどこまで具体化されるかを見ます。生成コマンドはbackendの出力を見ます。検証scriptとQEMU smokeは、Siltの外側に出た生成物が期待した形で残っているかを確認します。
