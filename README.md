# Silt

Low-level facts, lifted into typed values.

Silt is a stage0 Haskell bootstrap checker for an experimental systems
language. It uses an S-expression surface over a small CoC-style dependent core,
tracks value use with conservative quantities, and lowers selected low-level
programs through a first-order freestanding C path.

The current repository is a stage0 bootstrap, not a production compiler. Its
public claim is intentionally narrow: Silt can typecheck and lower a real subset
that reaches x86_64 ELF, Limine/QEMU smoke tests, typed static storage, and a
one-frame allocator handoff case study. It does not yet provide macros, a module
system, indexed inductive families, a general allocator, direct object
emission, self-hosting, or a production kernel.

## Start Here

- Official site: <https://m-simplifier.github.io/silt/>
- Silt Book: <https://m-simplifier.github.io/silt/book/>
- Current status and claim boundary: [STATUS.md](STATUS.md)
- Contribution and support policy: [CONTRIBUTING.md](CONTRIBUTING.md)

## What Works Today

- S-expression source forms with explicit `claim` / `def` boundaries.
- A small CoC-style dependent core with universes, `Pi`, annotated functions, `let`,
  application, normalization, and definitional equality.
- Quantities `0`, `1`, and `omega` for stage0 value-use checks.
- `Eff pre post A` as a small state-transition seed for ordered effects.
- Runtime-backed scalar and pointer primitives: `U8`, `U64`, `Addr`, `Ptr A`.
- Nominal `layout` declarations with size, alignment, field offsets, field
  projection, loads, stores, and layout literals.
- `static-bytes`, `static-cell`, and `static-value` for checked rodata, bss, and
  section-backed objects.
- Freestanding C emission for the supported first-order subset.
- Target and boot contracts for the current `x86_64-sysv-elf`,
  `x86_64-limine-elf`, and `limine-x86_64` bridges.
- QEMU-observed Limine smoke paths, including HHDM/Memmap response reads and an
  allocator handoff marker.

## Quick Checks

```bash
cabal test all
cabal run silt -- check examples/limine.silt
cabal run silt -- norm examples/limine.silt kernel-allocator-handoff-sample-ready
cabal run silt -- emit-freestanding-c examples/limine.silt limine-entry
scripts/verify-stage0-backend.sh
scripts/verify-freestanding-backend.sh
scripts/verify-x86_64-elf-backend.sh
scripts/verify-limine-bridge.sh
scripts/verify-limine-qemu-nix.sh
scripts/verify-limine-panic-qemu-nix.sh
```

The QEMU wrappers use Nix-provided tooling. If Nix is unavailable, the hosted
tests, generated-C checks, and link/bridge checks still cover the language and
backend subset that can run on the local machine.

## Build The Public Site

```bash
scripts/verify-public.sh
```

This builds the PureScript-generated landing page, the mdBook-based Silt Book,
and the public publication artifact under `out/site`.

## License

Silt is licensed under the [MIT License](LICENSE).
