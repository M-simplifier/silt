# Silt Status

Silt is public as an experimental stage0 research compiler. Treat every public
claim as limited to the checked subset in this repository.

## Defensible Claims

Silt currently demonstrates:

- a homoiconic S-expression surface for the implemented declaration and
  expression forms, including surface `if` sugar over `Bool` branches that
  desugars to `match`
- a small CoC-style dependent core with universes, `Pi`, normalization, and
  definitional equality
- conservative quantity-sensitive value-use checks for `0`, `1`, and `omega`
- a small effect-state seed with `Eff pre post A`
- low-level runtime representations through `U8`, `U64`, `Addr`, `Ptr A`,
  `layout`, `static-bytes` with explicit `u8` lists or narrow byte string
  literals, `static-cell`, and `static-value`
- freestanding C emission for supported first-order definitions
- a canonical formatter for the current S-expression source subset, with stdout
  formatting, non-mutating checks, and in-place writes
- a lint spine that combines canonical formatting checks with source-bundle
  parsing and checker diagnostics
- a diagnostics-only stdio LSP seed, `silt lsp`, that handles initialize,
  `textDocument/didOpen`, `textDocument/didChange`, `textDocument/didClose`,
  shutdown, and exit, and publishes formatter/parser/checker diagnostics for
  open document text
- lightweight Neovim filetype and syntax files for the current public surface
- a single-local-package `Silt.pkg` spine with `new`, `build`, `run`, `test`,
  and `doc` for no-argument hosted entry functions, plus argument forwarding,
  manifest-derived package docs, and exit status propagation through the hosted
  package harness
- a conservative standard-library seed with checker/normalizer-backed
  `Option` and `Result` helpers, including map/and-then-style combinators,
  plus a built-in checker/normalizer-backed `List` with option-shaped head/tail
  accessors and closed structural recursion through `list-elim`,
  `list-length`, `list-map`, `list-filter`, `list-append`, `list-reverse`, and
  `list-fold-right`; pure `Nat` addition,
  multiplication, predecessor, saturating subtraction, equality, and order
  helpers backed by `nat-elim`; explicit `ByteSlice` and `TextView` views over `U8` /
  `Ptr U8`; bounded pure view helpers for empty checks, `take`, and `drop`;
  byte-wise equality through `byte-slice-eq` and
  `text-eq`; prefix checks through `byte-slice-starts-with` and
  `text-starts-with`; suffix checks through `byte-slice-ends-with` and
  `text-ends-with`; first-byte find/contains/split helpers over explicit
  `ByteSlice` / `TextView` values; LF-oriented first-line split helpers over
  explicit `ByteSlice` / `TextView` values; single-byte count helpers over
  explicit `ByteSlice` / `TextView` values, including narrow LF wrappers; pure
  ASCII byte predicates over `U8` for digit, lower/upper alpha, alpha, alnum,
  hexadecimal digit, literal space, and ASCII whitespace classification; narrow
  all-ASCII slice/text predicates over
  explicit `ByteSlice` / `TextView` values for all-digits, all-alnum,
  all-hex-digits, and all-whitespace checks; narrow ASCII whitespace trimming
  over explicit `ByteSlice` / `TextView` values, returning allocation-free
  views into the original byte storage; a narrow ASCII decimal `U64` parser over
  explicit `ByteSlice` / `TextView` values that rejects empty input, non-digits,
  and overflow through an API-shaped `AsciiDecimalU64` layout result; narrow
  ASCII decimal `U64` formatting into caller-provided
  `AsciiDecimalU64Buffer` storage, returning an explicit `TextView` over the
  written bytes; an explicit `Nat` / `U64` bridge; and a first-order hosted
  text-output path that lowers through `nat-elim` to a C loop; and explicit hosted
  process-argument count/base/length boundaries with a `host-arg-text` view
  constructor; and explicit hosted environment presence/base/length boundaries
  with `host-env-has` and `host-env-text`; and a first-order hosted file-write
  boundary through `host-write-file`; and a first-order hosted file-read
  boundary through `host-read-file` with a narrow read-status observation; and
  a first-order `HostReadFileResult` body/status wrapper; and a first-order
  hosted stdin-read boundary through `host-read-stdin` with a narrow
  `HostReadStdinResult` body/status wrapper plus explicit stderr byte/text
  writers
- primitive-recursive factorial and Fibonacci examples over `Nat`, written with
  `nat-elim`, plus closed `List` length, map, filter, append, reverse, and fold
  examples written through `list-elim`, all tested through closed normalization
  plus package test targets
- root `hosted-hello`, `hosted-echo`, `hosted-env`, `hosted-exit`,
  `hosted-write-file`, `hosted-cat`, `hosted-copy`, `hosted-ascii-trim`,
  `hosted-size-report`, and
  `hosted-config-report` / `hosted-lf-count` / `hosted-stdin-lf-count` /
  `hosted-byte-drop` / `hosted-source-hygiene` / `hosted-byte-search` package
  examples that compile, run, print, read, write, report, count literal LF
  bytes from files or stdin, trim ASCII whitespace from files, drop matching
  bytes from stdin, check source-byte hygiene, or search for one byte through
  the hosted package harness, and
  exercise process status where relevant, plus
  `text-eq-test`, `text-prefix-test`,
  `text-suffix-test`, `text-scan-test`, `text-line-test`, `text-count-test`,
  `ascii-test`, `ascii-slice-test`, `ascii-trim-test`,
  `ascii-decimal-u64-test`, `ascii-decimal-u64-format-test`, and
  `nat-recursion-test` / `list-recursion-test` as package test targets
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
- a single-local-package `Silt.pkg` command spine with `new`, `build`, `run`,
  `test`, and `doc`, including generated bin/test scaffolds, selected package
  test execution through `silt test TARGET`, and manifest-derived HTML package
  docs at `out/silt/doc/index.html`
- a machine-readable diagnostics command, `silt diagnostics --json FILE...`,
  that reuses current lint facts from canonical formatting, source-bundle
  parsing, and checker diagnostics, emitting `silt.diagnostics.v0` JSON as an
  editor/LSP/AI-tooling seed
- a diagnostics-only stdio LSP seed, `silt lsp`, that uses the current
  formatter/parser/checker diagnostic machinery on one open document text
  buffer and publishes `textDocument/publishDiagnostics` notifications for
  opened, changed, or closed document text
- a hosted CLI pressure-test package target, `hosted-size-report`, that combines
  process args, a first-order file read result layout, ASCII decimal
  parse/format, file write, stdout, stderr diagnostics, and process status in
  one checked runnable example
- a hosted config-reading pressure-test package target,
  `hosted-config-report`, that combines two file reads, first-byte text split,
  ASCII whitespace trimming, static key comparison, ASCII decimal parse/format,
  file write, stdout, stderr diagnostics, and process status in one checked
  runnable example
- a hosted ASCII-trim package target, `hosted-ascii-trim`, that combines
  process args, file read, allocation-free ASCII whitespace trimming over an
  explicit `TextView`, file write, stdout, stderr diagnostics, and process
  status in one checked runnable example
- a hosted LF-count pressure-test package target, `hosted-lf-count`, that
  combines process args, file read, literal-LF byte counting over an explicit
  `TextView`, ASCII decimal formatting, file write, stdout, stderr diagnostics,
  and process status in one checked runnable example
- a hosted stdin LF-count filter package target, `hosted-stdin-lf-count`, that
  combines process arg-count validation, whole-stdin read into an explicit
  host-owned `TextView`, literal-LF byte counting, ASCII decimal formatting,
  stdout, stderr diagnostics, and process status in one checked runnable
  example
- a hosted byte-drop filter package target, `hosted-byte-drop`, that combines
  process arg-count validation, one-byte argument validation, whole-stdin read
  into an explicit host-owned `TextView`, byte-wise equality, effectful
  stdout byte writes for retained bytes, stderr diagnostics, and process status
  in one checked runnable example
- a hosted source-byte hygiene package target, `hosted-source-hygiene`, that
  combines process args, file read, explicit `TextView` byte-containment checks
  for NUL and CR, stdout/status reporting for `clean` / `nul` / `cr`, stderr
  diagnostics, and process status in one checked runnable example
- a hosted one-byte search pressure-test package target, `hosted-byte-search`,
  that combines process args, one-byte argument validation, file read,
  byte-containment search over an explicit `TextView`, stdout found/missing
  reporting, stderr diagnostics, and process status in one checked runnable
  example
- a hosted file-copy package target, `hosted-copy`, that combines process args,
  a first-order file read result layout, file write, stderr diagnostics, and
  process status in one checked runnable example
- a small hosted helper layer for diagnostic/status sequencing and
  caller-buffer ASCII decimal writes to stdout or explicit file paths, used by
  the hosted pressure-test examples without claiming a general hosted app
  framework

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
scripts/verify-hosted-copy.sh
scripts/verify-hosted-ascii-trim.sh
scripts/verify-stdlib-core-combinators.sh
scripts/verify-text-eq.sh
scripts/verify-text-prefix.sh
scripts/verify-text-suffix.sh
scripts/verify-text-scan.sh
scripts/verify-text-lines.sh
scripts/verify-text-count.sh
scripts/verify-ascii-predicates.sh
scripts/verify-ascii-slice-predicates.sh
scripts/verify-ascii-trim.sh
scripts/verify-ascii-decimal-u64.sh
scripts/verify-ascii-decimal-u64-format.sh
scripts/verify-text-view-helpers.sh
scripts/verify-stage0-backend.sh
scripts/verify-freestanding-backend.sh
scripts/verify-x86_64-elf-backend.sh
scripts/verify-limine-bridge.sh
scripts/verify-hosted-size-report.sh
scripts/verify-hosted-config-report.sh
scripts/verify-hosted-lf-count.sh
scripts/verify-hosted-stdin-lf-count.sh
scripts/verify-hosted-byte-drop.sh
scripts/verify-hosted-source-hygiene.sh
scripts/verify-hosted-byte-search.sh
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
- a package ecosystem, dependencies, workspaces, lockfiles, package publishing,
  package resolution, or selectable package templates
- mature LSP/editor tooling beyond the current diagnostics-only stdio seed,
  semantic highlighting, hover, completion, workspace-wide analysis,
  LSP-side source-bundle/include expansion, formatter-on-save integration, or
  editor package-manager plugins
- append modes, directory operations, path libraries, rich file-read error
  categories beyond the current success/failure status, allocator-backed Silt
  file buffers, streaming stdin, repeated stdin reads with independent
  lifetimes, `tr`-style byte translation, process spawning, signals,
  stdout/stderr abstractions beyond the current explicit byte/text writers,
  general hosted IO, environment enumeration or mutation, multi-file source
  traversal, in-place file editing, CRLF normalization, source-comment or
  type-signature API docs, cross-package docs, or package argument policy
  beyond `silt new NAME`, `silt run [TARGET] -- ARG...`, `silt test TARGET`,
  and `silt doc`
- indexed inductive families
- complete totality checking
- inferred ownership or a full aliasing discipline
- structural recursion for arbitrary user-defined data, dependent list
  induction, runtime code generation for generic `List` recursion, runtime
  representation for generic ADTs, open-term `List` algebraic laws, a broad
  sequence library, or general closure conversion
- Unicode categories, locale-sensitive behavior, case conversion, UTF-8
  validation, general string literals or a string type beyond the current
  `static-bytes` byte literal convenience, CRLF normalization, split-all line
  APIs, generic strings, arrays, dynamic slices, allocator-backed byte/text
  buffers, multi-byte search tools,
  substring/search/general scanning APIs beyond the current single-byte
  find/contains/split/count helpers, LF-oriented first-line split helpers,
  literal LF-byte counting, narrow all-ASCII class checks, ASCII decimal `U64`
  parser, ASCII decimal `U64` formatter, and narrow ASCII whitespace trimming,
  collation, line semantics beyond literal LF bytes, or text-normalization APIs
- decimal signs, radix prefixes, separators, whitespace trimming beyond the
  narrow ASCII view helper, detailed parse-error categories, signed formatting,
  radix formatting, padding, alignment, locale formatting, generic decimal
  output abstractions, or a general parser/formatter-combinator library
- multi-entry config formats, generic CLI/config parsing, or a general hosted
  app framework
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
