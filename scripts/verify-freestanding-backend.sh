#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

cd "$ROOT"

cabal build exe:silt
SILT_BIN="$(cabal list-bin exe:silt)"

"$SILT_BIN" emit-freestanding-c-bundle examples/freestanding.silt boot-header-remap boot-header-next init-header init-header-token read-magic read-next-via-layout read-next-via-layout-token inspect-header-platform boot-entry call-platform-zero reset-next reset-next-token reset-header-fields reset-header-fields-token init-and-read init-and-read-token > "$TMPDIR/freestanding.c"
"$SILT_BIN" abi-contracts examples/freestanding.silt > "$TMPDIR/freestanding.abi"

cc -std=c11 -Wall -Wextra -ffreestanding -fno-builtin -nostdlib -c \
  "$TMPDIR/freestanding.c" \
  -o "$TMPDIR/freestanding.o"

if ! nm "$TMPDIR/freestanding.o" | grep -q ' silt_boot_entry$'; then
  echo "missing exported freestanding symbol silt_boot_entry" >&2
  exit 1
fi

if ! objdump -h "$TMPDIR/freestanding.o" | grep -q '\.text\.silt\.boot'; then
  echo "missing freestanding section .text.silt.boot" >&2
  exit 1
fi

if ! grep -Fq '__attribute__((sysv_abi)) uint64_t platform_header_magic(silt_layout_Header hdr);' "$TMPDIR/freestanding.c"; then
  echo "missing freestanding extern sysv-abi attribute" >&2
  exit 1
fi

if ! grep -Fq '__attribute__((used)) __attribute__((sysv_abi)) __attribute__((section(".text.silt.boot"))) uint64_t silt_boot_entry(uintptr_t base) {' "$TMPDIR/freestanding.c"; then
  echo "missing freestanding entry sysv-abi/section attributes" >&2
  exit 1
fi

if ! grep -Fq 'abi-contract (entry) (symbol silt_boot_entry) (section .text.silt.boot) (calling-convention sysv-abi) (freestanding)' "$TMPDIR/freestanding.abi"; then
  echo "missing checked freestanding ABI contract" >&2
  exit 1
fi
