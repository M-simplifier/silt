# Summary

[はじめに](README.md)
[この本の読み方](preface.md)

# Part I: Siltを始める

- [1. Siltとは何か](01-what-is-silt.md)
- [2. 最初のSiltプログラム](02-first-program.md)
- [3. S式、宣言、評価](03-sexpr-declarations.md)
- [4. 型、`claim`、`def`](04-types-claims-defs.md)

# Part II: 依存型コア

- [5. `Pi`と関数](05-pi-functions.md)
- [6. 数量: `0`、`1`、`omega`](06-quantities.md)
- [7. データ型と`match`](07-data-match.md)
- [8. 正規化と等しさ](08-normalization.md)
- [9. Effect stateで副作用を制御する](09-effects.md)

# Part III: メモリと表現

- [10. `U8`、`U64`、`Addr`、`Ptr`](10-words-addresses-pointers.md)
- [11. `layout`: メモリ表現を型にする](11-layouts.md)
- [12. `load`、`store`、静的オブジェクト](12-memory-static.md)
- [13. ABI、C backend、freestanding](13-abi-c-freestanding.md)

# Part IV: カーネルへ降りる

- [14. Limineブート契約](14-limine-contracts.md)
- [15. シリアルI/Oとpanic](15-serial-panic.md)
- [16. ブート情報からカーネル情報へ](16-boot-info.md)
- [17. フレーム候補、予約、free-list seed](17-frame-seed.md)
- [18. allocator handoff](18-allocator-handoff.md)

# Part V: Siltを使い、理解する

- [19. テスト、検証、QEMU smoke](19-verification.md)
- [20. Siltが保証すること](20-status-and-guarantees.md)

# Appendices

- [A. 構文リファレンス](appendix-a-syntax-reference.md)
- [B. コマンドリファレンス](appendix-b-commands.md)
- [C. コンパイラ内部構造](appendix-c-compiler-internals.md)
