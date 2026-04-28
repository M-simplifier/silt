# 13. ABI、C backend、freestanding

Siltは、直接オブジェクトファイルを生成するのではなく、freestanding Cを生成し、そのCをコンパイル・リンクして低レイヤー実行物へ進みます。

この経路は逃げではありません。生成物を人間が読み、binutilsで確認し、QEMUで観測することを優先しています。

低レイヤーでは、言語内の型だけでは十分ではありません。外に出る名前、置かれるセクション、呼び出し規約、エントリ関数、linkerが見る形までそろって初めて、実行物になります。

関数を外部に出すには `export` を使います。

```lisp
(export limine-entry silt_limine_entry)
```

セクションを指定できます。

```lisp
(section limine-entry .text.silt.boot)
```

呼び出し規約も指定できます。

```lisp
(calling-convention limine-entry sysv-abi)
```

エントリ関数として指定します。

```lisp
(entry limine-entry)
```

これらのメタデータは、ただのコメントではありません。`abi-contract`、`target-contract`、`boot-contract` で検査されます。

```lisp
(abi-contract limine-entry
  ((entry)
   (symbol silt_limine_entry)
   (section .text.silt.boot)
   (calling-convention sysv-abi)
   (freestanding)))
```

`target-contract` は、生成物がどのターゲット向けかを表します。

```lisp
(target-contract x86_64-limine-elf
  ((format elf64)
   (arch x86_64)
   (abi sysv)
   (entry limine-entry)
   (symbol silt_limine_entry)
   (section .text.silt.boot)
   (calling-convention sysv-abi)
   (entry-address 18446744071562067968)
   (red-zone disabled)
   (freestanding)))
```

C backendは、Siltの `x86-out8` をinline asmへ落とします。

```c
__asm__ volatile ("outb %0, %1" : : "a"((uint8_t)(value)), "Nd"((uint16_t)(port)));
```

`static-cell` は `.bss.silt` のバイト配列に落ちます。

```c
static uint8_t silt_cell_limine_kernel_allocator_handoff[96]
  __attribute__((section(".bss.silt"), aligned(8)));
```

Siltの低レイヤー経路は、Siltからfreestanding Cを出し、C compilerとlinkerでELFを作り、検証scriptで構造を確認し、QEMUで起動する、というものです。

直接オブジェクト生成へ進む余地はあります。しかしこの本で扱う経路では、実装の正直さと検証可能性を優先してC backendを橋にしています。

ここで覚えるべきことは、C backendの存在ではなく、境界の読み方です。Siltの名前がCのシンボルへどう出るか。layoutがセクション上のバイト列へどう落ちるか。entryがbootloaderにどう見えるか。そこまでが、Siltの低レイヤー記述です。
