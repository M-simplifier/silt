# Appendix C: コンパイラ内部構造

SiltのコンパイラはHaskellで書かれています。構成は意図的に小さく分けられています。

この付録は、Siltを使うために必須ではありません。ただし、本文で何度も出てきた「型検査」「正規化」「C backend」「contract view」が、どのあたりで扱われるのかを知ると、Siltの保証をより読みやすくなります。

| モジュール | 役割 |
|---|---|
| `Silt.Syntax` | 構文木とpretty printer |
| `Silt.Parse` | lexer、S式parser、surface変換 |
| `Silt.Source` | file loading、include展開、source bundle |
| `Silt.Elab` | elaboration、type checking、NbE |
| `Silt.Codegen.C` | hosted/freestanding C backend |
| `Silt.CLI` | command line interface |

パイプラインは次の通りです。

```text
source files
  -> include expansion
  -> tokens
  -> S-expression tree
  -> surface declarations
  -> core terms
  -> type checking and normalization
  -> C emission / contract views
```

`Silt.Elab` は、Siltの意味論の中心です。ここで `Pi`、`fn`、`let`、`match`、数量チェック、`Eff`、builtin primitive、layout metadata、static objects、contract checksを扱います。

`Silt.Codegen.C` は、runtime-backed subsetをCへ落とします。`x86-out8` はinline asmへ、`static-cell` は `.bss.silt` のbyte objectへ、layout値はC側のaggregate representationへ変換されます。

C backendは狭いです。すべてのSiltプログラムをCへ落とせるわけではありません。第一級の依存型関数や任意の高階値を一般的にCへ出す段階ではありません。低レイヤー実行に必要なfirst-order runtime subsetを、検証可能な形で出しています。

これは設計上の選択です。Siltは、最初からLLVMや巨大な最適化基盤へ飛び込むのではなく、意味論と低レイヤー表現の対応を読みやすく保っています。

より明示的な中間表現や直接object emissionへ進む余地はあります。しかしこのコンパイラで重視しているのは、実装された意味と生成物が一致していることを確認しやすい構造です。

本文で見たSiltの姿勢は、コンパイラ内部にもそのまま現れています。大きな抽象へ急がず、構文、core、検査、生成物の境界を分ける。その分け方が、Siltの読みやすさと検証可能性を支えています。
