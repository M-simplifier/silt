# 19. テスト、検証、QEMU smoke

Siltでは、実装済みの主張を複数の層で検証します。

低レイヤーの言語では、「型が通った」だけでも、「起動した」だけでも足りません。型、正規化、生成C、ELF、ブート、QEMU観測が、それぞれ別の失敗を見つけます。

最も基本はテストです。

```bash
cabal test all
```

個別ファイルの型検査もあります。

```bash
cabal run silt -- check examples/limine.silt
```

正規化で、pureな証拠値を確認します。

```bash
cabal run silt -- norm examples/limine.silt kernel-allocator-handoff-sample-ready
```

freestanding Cを生成できます。

```bash
cabal run silt -- emit-freestanding-c examples/limine.silt limine-entry
```

生成Cだけでは不十分です。Siltでは検証scriptで、生成C、object symbol、section、linker output、target contract、boot contractを確認します。

```bash
scripts/verify-stage0-backend.sh
scripts/verify-freestanding-backend.sh
scripts/verify-x86_64-elf-backend.sh
scripts/verify-limine-bridge.sh
```

さらに、QEMUで実際に起動します。

```bash
scripts/verify-limine-qemu-nix.sh
scripts/verify-limine-panic-qemu-nix.sh
```

成功経路では、Silt由来のserial markerが出ます。panic経路では、panic markerとdebug-exit codeを確認します。

Siltの検証戦略は、「一つの強い証明だけで全部を語る」ものではありません。この本では、型検査、正規化、生成コード検査、linker検査、QEMU観測を重ねています。

この方針には理由があります。低レイヤーでは、型だけ正しくても、sectionが違えばbootloaderは見つけられません。Cが生成されても、ELF entryが違えば起動しません。QEMUで動いても、型上の境界が曖昧なら次の機能追加で壊れます。

Siltでは、各層の責任を分けて確認します。

これは保守的に見えますが、Siltの低レイヤー設計では重要な美点です。ひとつの層にすべてを押し込まず、型で言えること、生成物で言えること、実行観測で言えることを分ける。その分け方がはっきりしているほど、次の機能を足すときに、何を強めるべきかが見えます。
