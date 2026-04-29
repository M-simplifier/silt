# Maintainer Workflow

Silt is a public experimental research compiler. The repository should stay easy
to move, but `main` should remain a publishable line: green, explainable, and
safe to show.

## Default Flow

- Create a short-lived branch from `main` for every non-trivial change.
- Open a pull request before merging back to `main`.
- Use squash merge so public history stays readable.
- Delete merged branches after the pull request lands.
- Keep direct pushes to `main` for urgent repairs to broken publication,
  broken repository configuration, or a clearly understood CI failure.

This workflow is for maintainers. Outside contribution is issue-first; pull
requests from outside maintainers are not the normal route while Silt is still
experimental.

## Pull Request Gate

Every maintainer pull request should answer four questions:

- What changed?
- Did the public claim boundary stay the same, narrow, or widen?
- Which checks ran?
- Is every changed public file safe to publish?

If the public claim widens, the pull request should carry matching evidence in
code, tests, examples, documentation, and verification scripts.

## Separate Review Loop

Maintainer work may be implemented quickly, but merge should not be based only
on the same context that wrote the patch.

Default loop:

- The maintainer implements on a short-lived branch and opens a pull request.
- A separate maintainer session reviews the pull request with a strict review
  stance.
- The maintainer fixes any blocking findings and reruns the relevant checks.
- If checks are green and the separate review finds no blockers, the maintainer
  may squash-merge the pull request.
- The owner can still inspect the merged pull request history afterward and may
  interrupt this flow for boundary decisions, public-claim changes, or release
  timing.

This is a maintainer self-review workflow, not an invitation for outside pull
requests during the experimental stage.

## Check Matrix

For ordinary checker or parser changes:

```bash
cabal test all
git diff --check
```

For backend, ABI, target, or boot bridge changes, add the relevant scripts:

```bash
scripts/verify-stage0-backend.sh
scripts/verify-freestanding-backend.sh
scripts/verify-x86_64-elf-backend.sh
scripts/verify-limine-bridge.sh
```

For Limine runtime-smoke changes, run the QEMU checks when the local environment
has the needed tooling:

```bash
scripts/verify-limine-qemu-nix.sh
scripts/verify-limine-panic-qemu-nix.sh
```

For public documentation, site, licensing, contribution policy, or workflow
changes:

```bash
scripts/verify-public.sh
```

## Public File Rule

Before merging, review the staged or pull-request diff for local paths, personal
identifiers, access tokens, generated build output, and process notes that do
not belong in a public repository.
