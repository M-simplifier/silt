#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

cd "$ROOT"

cabal build exe:silt
SILT_BIN="$(cabal list-bin exe:silt)"
SERIAL_SOURCES=(examples/limine-serial.silt)
LIMINE_SOURCES=(examples/limine-serial.silt examples/limine.silt)
PANIC_SOURCES=(examples/limine-serial.silt examples/limine-panic.silt)

"$SILT_BIN" emit-freestanding-c-bundle "${SERIAL_SOURCES[@]}" -- serial-write-msg11 serial-write-msg15 serial-write-msg20 > "$TMPDIR/messages.c"
"$SILT_BIN" emit-freestanding-c-bundle "${LIMINE_SOURCES[@]}" -- limine-entry > "$TMPDIR/limine.c"
"$SILT_BIN" emit-freestanding-c-bundle "${PANIC_SOURCES[@]}" -- panic-entry > "$TMPDIR/panic.c"
"$SILT_BIN" emit-freestanding-c-bundle "${PANIC_SOURCES[@]}" -- kernel-panic-oom kernel-panic-invariant > "$TMPDIR/panic-causes.c"
"$SILT_BIN" target-contracts "${LIMINE_SOURCES[@]}" > "$TMPDIR/limine.target"
"$SILT_BIN" boot-contracts "${LIMINE_SOURCES[@]}" > "$TMPDIR/limine.boot"

cc -std=c11 -Wall -Wextra -ffreestanding -fno-builtin -fno-pic -fno-pie -fno-stack-protector -mno-red-zone -mcmodel=kernel -nostdlib -c \
  "$TMPDIR/messages.c" \
  -o "$TMPDIR/messages.o"

cc -std=c11 -Wall -Wextra -ffreestanding -fno-builtin -fno-pic -fno-pie -fno-stack-protector -mno-red-zone -mcmodel=kernel -nostdlib -c \
  "$TMPDIR/limine.c" \
  -o "$TMPDIR/limine.o"

cc -std=c11 -Wall -Wextra -ffreestanding -fno-builtin -fno-pic -fno-pie -fno-stack-protector -mno-red-zone -mcmodel=kernel -nostdlib -c \
  "$TMPDIR/panic.c" \
  -o "$TMPDIR/panic.o"

cc -std=c11 -Wall -Wextra -ffreestanding -fno-builtin -fno-pic -fno-pie -fno-stack-protector -mno-red-zone -mcmodel=kernel -nostdlib -c \
  "$TMPDIR/panic-causes.c" \
  -o "$TMPDIR/panic-causes.o"

ld -m elf_x86_64 -nostdlib -z max-page-size=0x1000 -T support/linker/x86_64-limine.ld \
  "$TMPDIR/limine.o" \
  -o "$TMPDIR/silt-limine.elf"

if ! grep -Fq 'target-contract x86_64-limine-elf (format elf64) (arch x86_64) (abi sysv) (entry limine-entry) (symbol silt_limine_entry) (section .text.silt.boot) (calling-convention sysv-abi) (entry-address 18446744071562067968) (red-zone disabled) (freestanding)' "$TMPDIR/limine.target"; then
  echo "missing checked x86_64 Limine target contract" >&2
  exit 1
fi

if ! grep -Fq 'boot-contract limine-x86_64 (protocol limine) (target x86_64-limine-elf) (entry limine-entry) (kernel-path /boot/silt-limine.elf) (config-path /boot/limine.conf) (freestanding)' "$TMPDIR/limine.boot"; then
  echo "missing checked Limine boot contract" >&2
  exit 1
fi

if ! grep -Fq '__asm__ volatile ("outb %0, %1" : : "a"((uint8_t)(80ULL)), "Nd"((uint16_t)(1016ULL)));' "$TMPDIR/panic.c"; then
  echo "generated panic entry does not emit the Silt panic marker" >&2
  exit 1
fi

if ! grep -Fq '__asm__ volatile ("outb %0, %1" : : "a"((uint8_t)(17ULL)), "Nd"((uint16_t)(244ULL)));' "$TMPDIR/panic.c"; then
  echo "generated panic entry does not emit the panic debug-exit code" >&2
  exit 1
fi

if ! nm "$TMPDIR/panic.o" | awk '$2 == "T" && $3 == "silt_limine_panic_entry" { found = 1 } END { exit found ? 0 : 1 }'; then
  echo "panic entry object is missing silt_limine_panic_entry" >&2
  exit 1
fi

if ! grep -Fq '__asm__ volatile ("outb %0, %1" : : "a"((uint8_t)(79ULL)), "Nd"((uint16_t)(1016ULL)));' "$TMPDIR/panic-causes.c"; then
  echo "generated OOM panic path does not emit the OOM marker suffix" >&2
  exit 1
fi

if ! grep -Fq '__asm__ volatile ("outb %0, %1" : : "a"((uint8_t)(18ULL)), "Nd"((uint16_t)(244ULL)));' "$TMPDIR/panic-causes.c"; then
  echo "generated OOM panic path does not emit the OOM debug-exit code" >&2
  exit 1
fi

if ! grep -Fq '__asm__ volatile ("outb %0, %1" : : "a"((uint8_t)(77ULL)), "Nd"((uint16_t)(1016ULL)));' "$TMPDIR/panic-causes.c"; then
  echo "generated OOM panic path does not emit the OOM marker M byte" >&2
  exit 1
fi

if ! grep -Fq '__asm__ volatile ("outb %0, %1" : : "a"((uint8_t)(86ULL)), "Nd"((uint16_t)(1016ULL)));' "$TMPDIR/panic-causes.c"; then
  echo "generated invariant panic path does not emit the invariant marker suffix" >&2
  exit 1
fi

if ! grep -Fq '__asm__ volatile ("outb %0, %1" : : "a"((uint8_t)(19ULL)), "Nd"((uint16_t)(244ULL)));' "$TMPDIR/panic-causes.c"; then
  echo "generated invariant panic path does not emit the invariant debug-exit code" >&2
  exit 1
fi

if ! nm "$TMPDIR/panic-causes.o" | awk '$2 == "T" && $3 == "kernel_panic_oom" { found = 1 } END { exit found ? 0 : 1 }'; then
  echo "panic causes object is missing kernel_panic_oom" >&2
  exit 1
fi

if ! nm "$TMPDIR/panic-causes.o" | awk '$2 == "T" && $3 == "kernel_panic_invariant" { found = 1 } END { exit found ? 0 : 1 }'; then
  echo "panic causes object is missing kernel_panic_invariant" >&2
  exit 1
fi

if ! grep -Fq 'uint8_t serial_write_msg20(silt_layout_SerialMsg20 msg) {' "$TMPDIR/messages.c"; then
  echo "generated serial message writer does not take a SerialMsg20 layout value" >&2
  exit 1
fi

if ! nm "$TMPDIR/messages.o" | awk '$2 == "T" && $3 == "serial_write_msg11" { found = 1 } END { exit found ? 0 : 1 }'; then
  echo "message writer object is missing serial_write_msg11" >&2
  exit 1
fi

if ! nm "$TMPDIR/messages.o" | awk '$2 == "T" && $3 == "serial_write_msg15" { found = 1 } END { exit found ? 0 : 1 }'; then
  echo "message writer object is missing serial_write_msg15" >&2
  exit 1
fi

if ! nm "$TMPDIR/messages.o" | awk '$2 == "T" && $3 == "serial_write_msg20" { found = 1 } END { exit found ? 0 : 1 }'; then
  echo "message writer object is missing serial_write_msg20" >&2
  exit 1
fi

ENTRY_SYMBOL="$(sed -n 's/.*(symbol \([^)]*\)).*/\1/p' "$TMPDIR/limine.target")"
ENTRY_SECTION="$(sed -n 's/.*(section \([^)]*\)).*/\1/p' "$TMPDIR/limine.target")"
ENTRY_ADDRESS_DEC="$(sed -n 's/.*(entry-address \([0-9][0-9]*\)).*/\1/p' "$TMPDIR/limine.target")"
KERNEL_PATH="$(sed -n 's/.*(kernel-path \([^)]*\)).*/\1/p' "$TMPDIR/limine.boot")"
CONFIG_PATH="$(sed -n 's/.*(config-path \([^)]*\)).*/\1/p' "$TMPDIR/limine.boot")"

if [ -z "$ENTRY_SYMBOL" ] || [ -z "$ENTRY_SECTION" ] || [ -z "$ENTRY_ADDRESS_DEC" ] || [ -z "$KERNEL_PATH" ] || [ -z "$CONFIG_PATH" ]; then
  echo "could not read checked Limine bridge facts" >&2
  exit 1
fi

if [ "$CONFIG_PATH" != "/boot/limine.conf" ]; then
  echo "unexpected checked Limine config path: $CONFIG_PATH" >&2
  exit 1
fi

CONFIG_FILE="support/limine/limine.conf"
ENTRY_ADDRESS_HEX="$(printf '0x%x' "$ENTRY_ADDRESS_DEC")"
ENTRY_ADDRESS_NM="$(printf '%016x' "$ENTRY_ADDRESS_DEC")"

if ! readelf -h "$TMPDIR/silt-limine.elf" | grep -Eq 'Class:[[:space:]]+ELF64'; then
  echo "Limine kernel artifact is not ELF64" >&2
  exit 1
fi

if ! readelf -h "$TMPDIR/silt-limine.elf" | grep -Eq 'Type:[[:space:]]+EXEC'; then
  echo "Limine kernel artifact is not an executable ELF" >&2
  exit 1
fi

if ! readelf -h "$TMPDIR/silt-limine.elf" | grep -Eq 'Machine:[[:space:]]+Advanced Micro Devices X86-64'; then
  echo "Limine kernel artifact is not x86_64" >&2
  exit 1
fi

if ! readelf -h "$TMPDIR/silt-limine.elf" | grep -Eq "Entry point address:[[:space:]]+$ENTRY_ADDRESS_HEX"; then
  echo "Limine kernel entry address is not $ENTRY_ADDRESS_HEX" >&2
  exit 1
fi

if ! nm "$TMPDIR/silt-limine.elf" | awk -v addr="$ENTRY_ADDRESS_NM" -v sym="$ENTRY_SYMBOL" '$1 == addr && $2 == "T" && $3 == sym { found = 1 } END { exit found ? 0 : 1 }'; then
  echo "Limine kernel entry symbol is not placed at $ENTRY_ADDRESS_HEX" >&2
  exit 1
fi

if ! objdump -h "$TMPDIR/silt-limine.elf" | awk -v section="$ENTRY_SECTION" -v addr="$ENTRY_ADDRESS_NM" '$2 == section && $4 == addr { found = 1 } END { exit found ? 0 : 1 }'; then
  echo "Limine kernel boot section is not placed at $ENTRY_ADDRESS_HEX" >&2
  exit 1
fi

if ! grep -Fq 'protocol: limine' "$CONFIG_FILE"; then
  echo "Limine config does not select the Limine protocol" >&2
  exit 1
fi

if ! grep -Fq "path: boot():$KERNEL_PATH" "$CONFIG_FILE"; then
  echo "Limine config kernel path does not match checked boot contract" >&2
  exit 1
fi
