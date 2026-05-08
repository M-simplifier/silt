# Silt Operator Guide

## Scope

This is the public AI-facing operator guide for Silt. Use it when working in a
fresh clone, choosing a maintainer task, or checking whether a change fits the
current public claim boundary.

Prefer repository artifacts over outside notes. A cold session should be able
to orient from this file plus the linked public docs.

## Read Order

1. `README.md`
2. `STATUS.md`
3. `CONTRIBUTING.md`
4. `MAINTAINERS.md`
5. `book/src/README.md` when the task touches the Book
6. the relevant source, example, test, or verifier script for the task
7. this file for workflow posture and operator defaults

The repository may have maintainer-local notes outside the tracked public tree.
Do not rely on those notes for public claims, and do not publish them by
accident.

## Project Posture

Silt is a public experimental stage0 research compiler. The current claim is
narrow: Silt can typecheck and lower an implemented subset that reaches
x86_64 ELF, Limine/QEMU smoke checks, typed static storage, and a one-frame
allocator handoff case study with a bounded live frame-pool cell update. It
also has early platform tooling: canonical formatting, lint through
formatter/parser/checker facts, a single-local-package hosted CLI spine, a
hosted stdlib seed with text output, process-argument reads, and environment
lookup, and lightweight Neovim filetype/syntax files.

Silt is not a production compiler, package ecosystem, mature editor/LSP
platform, self-hosted compiler, finished operating system, general allocator,
or end-to-end verified compiler.

## Goal-Driven Work

Owner-facing work is managed by explicit Goals. A Goal should describe a
reviewable result, acceptance criteria, allowed side effects, verification
requirements, and stop conditions.

Inside a Goal, maintainers may choose their own implementation slices, branch
shape, and verification order. Do not require the owner to manage internal task
grain. Report back when the Goal is complete, when the public claim boundary
would change, when outside action is needed, or when verification cannot cover
the intended result.

## Public Claim Boundary

Every new claim should be backed by all of the following:

- checker or parser behavior where relevant
- examples or fixtures that exercise the behavior
- tests or verifier scripts
- public docs or status text if the claim is user-facing
- a clear non-claim boundary for adjacent features

Keep planned features visibly separate from implemented behavior. Do not imply
macros, modules, indexed families, general allocation, broad memory-map parsing,
direct object emission, self-hosting, or a complete kernel unless the repository
contains matching evidence.

## Workflow

- Keep `main` publishable: green, explainable, and safe to show.
- Use short-lived branches and pull requests for non-trivial maintainer work.
- Use squash merge and delete merged branches.
- Keep direct pushes to `main` for urgent publication, repository
  configuration, or clearly understood CI repair.
- Treat public docs, site, Book, workflows, and operator guidance as public
  artifacts that require the same safety review as source changes.

## Check Matrix

For parser, checker, or language changes:

```bash
cabal test all
git diff --check
```

For platform tooling, package, stdlib, or editor-surface changes, add the
relevant verifier:

```bash
scripts/verify-platform-tools.sh
scripts/verify-editor-tools.sh
scripts/verify-package-spine.sh
scripts/verify-stdlib-hosted-seed.sh
scripts/verify-hosted-args.sh
scripts/verify-hosted-env.sh
scripts/verify-text-view-helpers.sh
```

For backend, ABI, target, or boot bridge changes, add the relevant verifier:

```bash
scripts/verify-stage0-backend.sh
scripts/verify-freestanding-backend.sh
scripts/verify-x86_64-elf-backend.sh
scripts/verify-limine-bridge.sh
```

For Limine runtime-smoke changes, run QEMU checks when the local environment has
the needed tooling:

```bash
scripts/verify-limine-qemu-nix.sh
scripts/verify-limine-panic-qemu-nix.sh
```

For public documentation, site, Book, licensing, contribution policy, workflow,
or operator guidance changes:

```bash
scripts/verify-public.sh
```

## Public File Review

Before opening or merging a pull request, inspect the changed public files for:

- local paths or machine-specific assumptions
- personal identifiers
- credentials or access tokens
- generated build output
- unpublished planning notes or coordination language
- maturity or safety claims stronger than the checks prove

If the change widens the public claim boundary, the pull request should include
matching implementation evidence and verification commands.
