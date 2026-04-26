#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

cd "$ROOT"

for tool in cc ld readelf nm objdump limine qemu-system-x86_64; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    echo "missing required tool: $tool" >&2
    exit 1
  fi
done

if [ -z "${OVMF_FD:-}" ]; then
  OVMF_FD="$(find /nix/store -maxdepth 4 -type f -path '*/FV/OVMF.fd' -print -quit 2>/dev/null || true)"
fi

if [ -z "$OVMF_FD" ] || [ ! -f "$OVMF_FD" ]; then
  echo "missing OVMF firmware; set OVMF_FD to an OVMF.fd path" >&2
  exit 1
fi

cabal build exe:silt
SILT_BIN="$(cabal list-bin exe:silt)"
PANIC_SOURCES=(examples/limine-serial.silt examples/limine-panic.silt)

"$SILT_BIN" emit-freestanding-c-bundle "${PANIC_SOURCES[@]}" -- panic-entry > "$TMPDIR/panic.c"
"$SILT_BIN" target-contracts "${PANIC_SOURCES[@]}" > "$TMPDIR/panic.target"
"$SILT_BIN" boot-contracts "${PANIC_SOURCES[@]}" > "$TMPDIR/panic.boot"

cc -std=c11 -Wall -Wextra -ffreestanding -fno-builtin -fno-pic -fno-pie -fno-stack-protector -mno-red-zone -mcmodel=kernel -nostdlib -c \
  "$TMPDIR/panic.c" \
  -o "$TMPDIR/panic.o"

ENTRY_SYMBOL="$(sed -n 's/.*(symbol \([^)]*\)).*/\1/p' "$TMPDIR/panic.target")"
ENTRY_SECTION="$(sed -n 's/.*(section \([^)]*\)).*/\1/p' "$TMPDIR/panic.target")"
ENTRY_ADDRESS_DEC="$(sed -n 's/.*(entry-address \([0-9][0-9]*\)).*/\1/p' "$TMPDIR/panic.target")"
KERNEL_PATH="$(sed -n 's/.*(kernel-path \([^)]*\)).*/\1/p' "$TMPDIR/panic.boot")"
CONFIG_PATH="$(sed -n 's/.*(config-path \([^)]*\)).*/\1/p' "$TMPDIR/panic.boot")"

if [ -z "$ENTRY_SYMBOL" ] || [ -z "$ENTRY_SECTION" ] || [ -z "$ENTRY_ADDRESS_DEC" ] || [ -z "$KERNEL_PATH" ] || [ -z "$CONFIG_PATH" ]; then
  echo "could not read checked Limine panic QEMU facts" >&2
  exit 1
fi

ld -m elf_x86_64 -nostdlib -z max-page-size=0x1000 -e "$ENTRY_SYMBOL" -T support/linker/x86_64-limine.ld \
  "$TMPDIR/panic.o" \
  -o "$TMPDIR/silt-limine.elf"

ENTRY_ADDRESS_HEX="$(printf '0x%x' "$ENTRY_ADDRESS_DEC")"
ENTRY_ADDRESS_NM="$(printf '%016x' "$ENTRY_ADDRESS_DEC")"

if ! readelf -h "$TMPDIR/silt-limine.elf" | grep -Eq "Entry point address:[[:space:]]+$ENTRY_ADDRESS_HEX"; then
  echo "Limine panic QEMU artifact entry address is not $ENTRY_ADDRESS_HEX" >&2
  exit 1
fi

if ! nm "$TMPDIR/silt-limine.elf" | awk -v addr="$ENTRY_ADDRESS_NM" -v sym="$ENTRY_SYMBOL" '$1 == addr && $2 == "T" && $3 == sym { found = 1 } END { exit found ? 0 : 1 }'; then
  echo "Limine panic QEMU artifact entry symbol is not placed at $ENTRY_ADDRESS_HEX" >&2
  exit 1
fi

if ! objdump -h "$TMPDIR/silt-limine.elf" | awk -v section="$ENTRY_SECTION" -v addr="$ENTRY_ADDRESS_NM" '$2 == section && $4 == addr { found = 1 } END { exit found ? 0 : 1 }'; then
  echo "Limine panic QEMU artifact boot section is not placed at $ENTRY_ADDRESS_HEX" >&2
  exit 1
fi

if [ "$CONFIG_PATH" != "/boot/limine.conf" ]; then
  echo "unexpected checked Limine panic config path: $CONFIG_PATH" >&2
  exit 1
fi

ESP="$TMPDIR/esp"
mkdir -p "$ESP/EFI/BOOT" "$ESP/boot"
cp "$(limine --print-datadir)/BOOTX64.EFI" "$ESP/EFI/BOOT/BOOTX64.EFI"
cp support/limine/limine.conf "$ESP$CONFIG_PATH"
cp "$TMPDIR/silt-limine.elf" "$ESP$KERNEL_PATH"
cat > "$ESP/startup.nsh" <<'EOF'
fs0:\efi\boot\bootx64.efi
EOF

if ! grep -Fq 'protocol: limine' "$ESP$CONFIG_PATH"; then
  echo "Limine panic QEMU config does not select the Limine protocol" >&2
  exit 1
fi

if ! grep -Fq "path: boot():$KERNEL_PATH" "$ESP$CONFIG_PATH"; then
  echo "Limine panic QEMU config kernel path does not match checked boot contract" >&2
  exit 1
fi

SERIAL_LOG="$TMPDIR/serial.log"
set +e
timeout 20s qemu-system-x86_64 \
  -M q35 \
  -m 256M \
  -accel tcg \
  -bios "$OVMF_FD" \
  -drive if=ide,format=raw,file=fat:rw:"$ESP" \
  -serial file:"$SERIAL_LOG" \
  -display none \
  -no-reboot \
  -device isa-debug-exit,iobase=0xf4,iosize=0x04
QEMU_STATUS=$?
set -e

if [ "$QEMU_STATUS" -ne 35 ]; then
  echo "QEMU did not exit through the Silt panic debug-exit path; status $QEMU_STATUS" >&2
  if [ -f "$SERIAL_LOG" ]; then
    sed -n '1,120p' "$SERIAL_LOG" >&2
  fi
  exit 1
fi

if ! grep -Fq "SILT_PANIC" "$SERIAL_LOG"; then
  echo "QEMU serial log did not contain the Silt panic marker" >&2
  sed -n '1,120p' "$SERIAL_LOG" >&2
  exit 1
fi

echo "Limine panic QEMU smoke passed: panic entry reached and debug-exit marker observed"
