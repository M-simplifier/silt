#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

cd "$ROOT"

cabal build exe:silt
SILT_BIN="$(cabal list-bin exe:silt)"

"$SILT_BIN" emit-freestanding-c-bundle examples/freestanding.silt boot-header-remap boot-header-next init-header init-header-token read-magic read-next-via-layout read-next-via-layout-token inspect-header-platform boot-entry call-platform-zero reset-next reset-next-token reset-header-fields reset-header-fields-token init-and-read init-and-read-token > "$TMPDIR/kernel.c"
"$SILT_BIN" abi-contracts examples/freestanding.silt > "$TMPDIR/kernel.abi"
"$SILT_BIN" target-contracts examples/freestanding.silt > "$TMPDIR/kernel.target"

cat >> "$TMPDIR/kernel.c" <<'EOF'

__attribute__((sysv_abi)) uint64_t platform_header_magic(silt_layout_Header hdr) {
  return (*((uint64_t*)(((uintptr_t)&hdr + 0ULL))));
}

uint8_t platform_header_zero(uintptr_t ptr) {
  (void)ptr;
  return 0;
}
EOF

cc -std=c11 -Wall -Wextra -ffreestanding -fno-builtin -fno-pic -fno-pie -fno-stack-protector -mno-red-zone -nostdlib -c \
  "$TMPDIR/kernel.c" \
  -o "$TMPDIR/kernel.o"

ld -m elf_x86_64 -nostdlib -T support/linker/x86_64-sysv-elf.ld \
  "$TMPDIR/kernel.o" \
  -o "$TMPDIR/kernel.elf"

if ! grep -Fq 'abi-contract (entry) (symbol silt_boot_entry) (section .text.silt.boot) (calling-convention sysv-abi) (freestanding)' "$TMPDIR/kernel.abi"; then
  echo "missing checked x86_64 SysV ELF ABI contract" >&2
  exit 1
fi

if ! grep -Fq 'target-contract x86_64-sysv-elf (format elf64) (arch x86_64) (abi sysv) (entry boot-entry) (symbol silt_boot_entry) (section .text.silt.boot) (calling-convention sysv-abi) (entry-address 1048576) (red-zone disabled) (freestanding)' "$TMPDIR/kernel.target"; then
  echo "missing checked x86_64 SysV ELF target contract" >&2
  exit 1
fi

ENTRY_SYMBOL="$(sed -n 's/.*(symbol \([^)]*\)).*/\1/p' "$TMPDIR/kernel.target")"
ENTRY_SECTION="$(sed -n 's/.*(section \([^)]*\)).*/\1/p' "$TMPDIR/kernel.target")"
ENTRY_ADDRESS_DEC="$(sed -n 's/.*(entry-address \([0-9][0-9]*\)).*/\1/p' "$TMPDIR/kernel.target")"

if [ -z "$ENTRY_SYMBOL" ] || [ -z "$ENTRY_SECTION" ] || [ -z "$ENTRY_ADDRESS_DEC" ]; then
  echo "could not read entry facts from checked target contract" >&2
  exit 1
fi

ENTRY_ADDRESS_HEX="$(printf '0x%x' "$ENTRY_ADDRESS_DEC")"
ENTRY_ADDRESS_NM="$(printf '%016x' "$ENTRY_ADDRESS_DEC")"

if ! readelf -h "$TMPDIR/kernel.elf" | grep -Eq 'Class:[[:space:]]+ELF64'; then
  echo "linked kernel artifact is not ELF64" >&2
  exit 1
fi

if ! readelf -h "$TMPDIR/kernel.elf" | grep -Eq 'Type:[[:space:]]+EXEC'; then
  echo "linked kernel artifact is not an executable ELF" >&2
  exit 1
fi

if ! readelf -h "$TMPDIR/kernel.elf" | grep -Eq 'Machine:[[:space:]]+Advanced Micro Devices X86-64'; then
  echo "linked kernel artifact is not x86_64" >&2
  exit 1
fi

if ! readelf -h "$TMPDIR/kernel.elf" | grep -Eq "Entry point address:[[:space:]]+$ENTRY_ADDRESS_HEX"; then
  echo "linked kernel entry address is not $ENTRY_ADDRESS_HEX" >&2
  exit 1
fi

if ! nm "$TMPDIR/kernel.elf" | awk -v addr="$ENTRY_ADDRESS_NM" -v sym="$ENTRY_SYMBOL" '$1 == addr && $2 == "T" && $3 == sym { found = 1 } END { exit found ? 0 : 1 }'; then
  echo "linked kernel entry symbol is not placed at $ENTRY_ADDRESS_HEX" >&2
  exit 1
fi

if ! readelf -S "$TMPDIR/kernel.elf" | grep -Fq "$ENTRY_SECTION"; then
  echo "linked kernel artifact is missing $ENTRY_SECTION" >&2
  exit 1
fi

if ! objdump -h "$TMPDIR/kernel.elf" | awk -v section="$ENTRY_SECTION" -v addr="$ENTRY_ADDRESS_NM" '$2 == section && $4 == addr { found = 1 } END { exit found ? 0 : 1 }'; then
  echo "linked kernel boot section is not placed at $ENTRY_ADDRESS_HEX" >&2
  exit 1
fi
