# Silt Status

Silt is public as an experimental stage0 research compiler. Treat every public
claim as limited to the checked subset in this repository.

## Defensible Claims

Silt currently demonstrates:

- a homoiconic S-expression surface for the implemented declaration and
  expression forms
- a small CoC-style dependent core with universes, `Pi`, normalization, and
  definitional equality
- conservative quantity-sensitive value-use checks for `0`, `1`, and `omega`
- a small effect-state seed with `Eff pre post A`
- low-level runtime representations through `U8`, `U64`, `Addr`, `Ptr A`,
  `layout`, `static-bytes`, `static-cell`, and `static-value`
- freestanding C emission for supported first-order definitions
- a canonical formatter/checker for the current S-expression source subset
- a lint spine that combines canonical formatting checks with source-bundle
  parsing and checker diagnostics
- lightweight Neovim filetype and syntax files for the current public surface
- a single-local-package `Silt.pkg` spine with `build`, `run`, and `test` for
  no-argument hosted entry functions, plus `silt run [TARGET] -- ARG...`
  forwarding and exit status propagation through the hosted package harness
- a conservative standard-library seed with checker/normalizer-backed
  `Option`, `Result`, and `List` helpers; explicit `ByteSlice` and `TextView`
  views over `U8` / `Ptr U8`; bounded pure view helpers for empty checks,
  `take`, and `drop`; byte-wise equality through `byte-slice-eq` and
  `text-eq`; an explicit `Nat` / `U64` bridge; and a first-order hosted
  text-output path that lowers through `nat-elim` to a C loop; and explicit
  hosted process-argument count/base/length boundaries with a
  `host-arg-text` view constructor; and explicit hosted environment
  presence/base/length boundaries with `host-env-has` and `host-env-text`; and
  a first-order hosted file-write boundary through `host-write-file`; and a
  first-order hosted file-read boundary through `host-read-file`
- root `hosted-hello`, `hosted-echo`, `hosted-env`, `hosted-exit`, and
  `hosted-write-file` and `hosted-cat` package examples that compile, run,
  print, read, or write through the hosted package harness, and exercise
  process status where relevant, plus `text-eq-test` as a package test target
- ABI, target, and boot contract checks for the current x86_64 and Limine
  bridges
- generated-code, object, linker, and QEMU marker-observation evidence for the
  Limine smoke path
- a one-frame allocator handoff case study built from typed boot facts, frame
  candidate records, reservation state, a free-list seed, alloc/free trace
  records, API-shaped results, a semantics witness, a lease record, and a final
  handoff object
- a bounded live frame-pool cell update inside the Limine path: seed state is
  stored, loaded, updated to an allocated state, stored again, restored through
  a free transition, and QEMU observes the final readiness marker

## Current Evidence

The strongest local checks are:

```bash
cabal test all
cabal run silt -- check examples/limine.silt
cabal run silt -- norm examples/limine.silt kernel-allocator-handoff-sample-ready
cabal run silt -- norm examples/limine.silt kernel-frame-pool-live-restored-sample-ready
scripts/verify-platform-tools.sh
scripts/verify-editor-tools.sh
scripts/verify-package-spine.sh
scripts/verify-stdlib-hosted-seed.sh
scripts/verify-hosted-args.sh
scripts/verify-hosted-env.sh
scripts/verify-hosted-exit.sh
scripts/verify-hosted-file-write.sh
scripts/verify-hosted-file-read.sh
scripts/verify-text-eq.sh
scripts/verify-text-view-helpers.sh
scripts/verify-stage0-backend.sh
scripts/verify-freestanding-backend.sh
scripts/verify-x86_64-elf-backend.sh
scripts/verify-limine-bridge.sh
scripts/verify-limine-qemu-nix.sh
scripts/verify-limine-panic-qemu-nix.sh
scripts/verify-public.sh
```

The QEMU checks are smoke tests, not full hardware validation and not
fail-closed kernel validation. They prove that the current generated artifact
boots far enough under the configured environment for the verifier to observe
the expected serial/debug-exit markers.

## Non-Claims

Silt does not currently claim:

- production readiness
- a macro system
- a module/import system beyond the current source include convenience
- a package ecosystem, dependencies, workspaces, or lockfiles
- mature LSP/editor tooling, semantic highlighting, or formatter-on-save
  integration
- append modes, directory operations, path libraries, missing-vs-empty file-read
  error distinctions, allocator-backed Silt file buffers, process spawning,
  signals, stdout/stderr abstractions, general hosted IO, environment
  enumeration or mutation, or package argument policy beyond
  `silt run [TARGET] -- ARG...`
- runtime representation for generic ADTs
- indexed inductive families
- complete totality checking
- inferred ownership or a full aliasing discipline
- UTF-8 validation, generic strings, arrays, dynamic slices, allocator-backed
  byte/text buffers, substring/search/scanning APIs, collation, or
  text-normalization APIs
- a complete Limine or memory-map parser
- a general allocator
- a mutating free-list allocator
- multi-frame allocation
- a production allocator
- direct object or binary emission
- self-hosting
- a complete kernel or OS
- formal verification of the whole compiler or kernel

## Operating Posture

The project is moving by evidence-bearing slices. New language claims should be
public only when they have checker support, examples, tests, documentation, and
an executable verification path.

Maintainer work is Goal-driven. The owner should be asked to manage reviewable
Goals and public-boundary decisions, not internal implementation slices. See
[AGENTS.md](AGENTS.md) and [MAINTAINERS.md](MAINTAINERS.md) for the public
operator and maintainer workflow.
