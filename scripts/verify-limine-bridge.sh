#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

cd "$ROOT"

cabal build exe:silt
SILT_BIN="$(cabal list-bin exe:silt)"
SERIAL_SOURCES=(examples/limine-serial.silt)
LIMINE_SOURCES=(examples/limine.silt)
PANIC_SOURCES=(examples/limine-panic.silt)

"$SILT_BIN" emit-freestanding-c-bundle "${SERIAL_SOURCES[@]}" -- serial-write-msg11 serial-write-msg15 serial-write-msg20 serial-write-slice20 > "$TMPDIR/messages.c"
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

if ! grep -Fq 'static const uint8_t silt_static_limine_ok_bytes[20] __attribute__((section(".rodata.silt"))) = {83u, 73u, 76u, 84u, 95u, 76u, 73u, 77u, 73u, 78u, 69u, 95u, 81u, 69u, 77u, 85u, 95u, 79u, 75u, 10u};' "$TMPDIR/limine.c"; then
  echo "generated Limine entry does not emit the success message as static rodata bytes" >&2
  exit 1
fi

if ! grep -Fq 'static const uint8_t silt_static_limine_boot_info_ok_bytes[20] __attribute__((section(".rodata.silt"))) = {83u, 73u, 76u, 84u, 95u, 66u, 79u, 79u, 84u, 95u, 73u, 78u, 70u, 79u, 95u, 79u, 75u, 33u, 33u, 10u};' "$TMPDIR/limine.c"; then
  echo "generated Limine entry does not emit the boot-info marker as static rodata bytes" >&2
  exit 1
fi

if ! grep -Fq 'static const uint8_t silt_static_limine_boot_span_ok_bytes[20] __attribute__((section(".rodata.silt"))) = {83u, 73u, 76u, 84u, 95u, 66u, 79u, 79u, 84u, 95u, 83u, 80u, 65u, 78u, 95u, 79u, 75u, 33u, 33u, 10u};' "$TMPDIR/limine.c"; then
  echo "generated Limine entry does not emit the boot-span marker as static rodata bytes" >&2
  exit 1
fi

if ! grep -Fq 'static const uint8_t silt_static_limine_kernel_span_ok_bytes[20] __attribute__((section(".rodata.silt"))) = {83u, 73u, 76u, 84u, 95u, 75u, 69u, 82u, 78u, 69u, 76u, 95u, 83u, 80u, 65u, 78u, 95u, 79u, 75u, 10u};' "$TMPDIR/limine.c"; then
  echo "generated Limine entry does not emit the kernel-span marker as static rodata bytes" >&2
  exit 1
fi

if ! grep -Fq 'static const uint8_t silt_static_limine_kernel_pages_ok_bytes[20] __attribute__((section(".rodata.silt"))) = {83u, 73u, 76u, 84u, 95u, 75u, 80u, 65u, 71u, 69u, 83u, 95u, 79u, 75u, 33u, 33u, 33u, 33u, 33u, 10u};' "$TMPDIR/limine.c"; then
  echo "generated Limine entry does not emit the kernel-pages marker as static rodata bytes" >&2
  exit 1
fi

if ! grep -Fq 'static const uint8_t silt_static_limine_boot_policy_ok_bytes[20] __attribute__((section(".rodata.silt"))) = {83u, 73u, 76u, 84u, 95u, 66u, 79u, 79u, 84u, 95u, 80u, 79u, 76u, 73u, 67u, 89u, 95u, 79u, 75u, 10u};' "$TMPDIR/limine.c"; then
  echo "generated Limine entry does not emit the boot-policy marker as static rodata bytes" >&2
  exit 1
fi

if ! grep -Fq 'static const uint8_t silt_static_limine_boot_plan_ok_bytes[20] __attribute__((section(".rodata.silt"))) = {83u, 73u, 76u, 84u, 95u, 66u, 79u, 79u, 84u, 95u, 80u, 76u, 65u, 78u, 95u, 79u, 75u, 33u, 33u, 10u};' "$TMPDIR/limine.c"; then
  echo "generated Limine entry does not emit the boot-plan marker as static rodata bytes" >&2
  exit 1
fi

if ! grep -Fq 'static const uint8_t silt_static_limine_plan_invariant_ok_bytes[20] __attribute__((section(".rodata.silt"))) = {83u, 73u, 76u, 84u, 95u, 80u, 76u, 65u, 78u, 95u, 73u, 78u, 86u, 95u, 79u, 75u, 33u, 33u, 33u, 10u};' "$TMPDIR/limine.c"; then
  echo "generated Limine entry does not emit the plan-invariant marker as static rodata bytes" >&2
  exit 1
fi

if ! grep -Fq 'static const uint8_t silt_static_limine_frame_candidate_ok_bytes[20] __attribute__((section(".rodata.silt"))) = {83u, 73u, 76u, 84u, 95u, 70u, 82u, 65u, 77u, 69u, 95u, 67u, 65u, 78u, 68u, 95u, 79u, 75u, 33u, 10u};' "$TMPDIR/limine.c"; then
  echo "generated Limine entry does not emit the frame-candidate marker as static rodata bytes" >&2
  exit 1
fi

if ! grep -Fq 'static const uint8_t silt_static_limine_frame_eligibility_ok_bytes[20] __attribute__((section(".rodata.silt"))) = {83u, 73u, 76u, 84u, 95u, 70u, 82u, 65u, 77u, 69u, 95u, 69u, 76u, 73u, 71u, 95u, 79u, 75u, 33u, 10u};' "$TMPDIR/limine.c"; then
  echo "generated Limine entry does not emit the frame-eligibility marker as static rodata bytes" >&2
  exit 1
fi

if ! grep -Fq 'static const uint8_t silt_static_limine_frame_reservation_ok_bytes[20] __attribute__((section(".rodata.silt"))) = {83u, 73u, 76u, 84u, 95u, 70u, 82u, 65u, 77u, 69u, 95u, 82u, 69u, 83u, 86u, 95u, 79u, 75u, 33u, 10u};' "$TMPDIR/limine.c"; then
  echo "generated Limine entry does not emit the frame-reservation marker as static rodata bytes" >&2
  exit 1
fi

if ! grep -Fq 'static const uint8_t silt_static_limine_frame_reservation_invariant_ok_bytes[20] __attribute__((section(".rodata.silt"))) = {83u, 73u, 76u, 84u, 95u, 82u, 69u, 83u, 86u, 95u, 73u, 78u, 86u, 95u, 79u, 75u, 33u, 33u, 33u, 10u};' "$TMPDIR/limine.c"; then
  echo "generated Limine entry does not emit the frame-reservation-invariant marker as static rodata bytes" >&2
  exit 1
fi

if ! grep -Fq 'static const uint8_t silt_static_limine_frame_reservation_state_ok_bytes[20] __attribute__((section(".rodata.silt"))) = {83u, 73u, 76u, 84u, 95u, 70u, 82u, 65u, 77u, 69u, 95u, 82u, 83u, 86u, 68u, 95u, 79u, 75u, 33u, 10u};' "$TMPDIR/limine.c"; then
  echo "generated Limine entry does not emit the frame-reservation-state marker as static rodata bytes" >&2
  exit 1
fi

if ! grep -Fq 'static const uint8_t silt_static_limine_frame_free_list_seed_ok_bytes[20] __attribute__((section(".rodata.silt"))) = {83u, 73u, 76u, 84u, 95u, 70u, 76u, 73u, 83u, 84u, 95u, 83u, 69u, 69u, 68u, 95u, 79u, 75u, 33u, 10u};' "$TMPDIR/limine.c"; then
  echo "generated Limine entry does not emit the frame free-list seed marker as static rodata bytes" >&2
  exit 1
fi

if ! grep -Fq 'static const uint8_t silt_static_limine_frame_alloc_one_ok_bytes[20] __attribute__((section(".rodata.silt"))) = {83u, 73u, 76u, 84u, 95u, 65u, 76u, 76u, 79u, 67u, 95u, 79u, 78u, 69u, 95u, 79u, 75u, 33u, 33u, 10u};' "$TMPDIR/limine.c"; then
  echo "generated Limine entry does not emit the frame alloc-one marker as static rodata bytes" >&2
  exit 1
fi

if ! grep -Fq 'static const uint8_t silt_static_limine_frame_free_one_ok_bytes[20] __attribute__((section(".rodata.silt"))) = {83u, 73u, 76u, 84u, 95u, 70u, 82u, 69u, 69u, 95u, 79u, 78u, 69u, 95u, 79u, 75u, 33u, 33u, 33u, 10u};' "$TMPDIR/limine.c"; then
  echo "generated Limine entry does not emit the frame free-one marker as static rodata bytes" >&2
  exit 1
fi

if ! grep -Fq 'static uint8_t silt_cell_limine_boot_state[16] __attribute__((section(".bss.silt"), aligned(8)));' "$TMPDIR/limine.c"; then
  echo "generated Limine entry does not emit the typed boot-state static cell in bss" >&2
  exit 1
fi

if ! grep -Fq 'static uint8_t silt_cell_limine_boot_info[40] __attribute__((section(".bss.silt"), aligned(8)));' "$TMPDIR/limine.c"; then
  echo "generated Limine entry does not emit the typed boot-info static cell in bss" >&2
  exit 1
fi

if ! grep -Fq 'static uint8_t silt_cell_limine_kernel_span[40] __attribute__((section(".bss.silt"), aligned(8)));' "$TMPDIR/limine.c"; then
  echo "generated Limine entry does not emit the typed kernel-span static cell in bss" >&2
  exit 1
fi

if ! grep -Fq 'static uint8_t silt_cell_limine_kernel_page_count[8] __attribute__((section(".bss.silt"), aligned(8)));' "$TMPDIR/limine.c"; then
  echo "generated Limine entry does not emit the typed kernel page-count static cell in bss" >&2
  exit 1
fi

if ! grep -Fq 'static uint8_t silt_cell_limine_kernel_policy[24] __attribute__((section(".bss.silt"), aligned(8)));' "$TMPDIR/limine.c"; then
  echo "generated Limine entry does not emit the typed kernel policy static cell in bss" >&2
  exit 1
fi

if ! grep -Fq 'static uint8_t silt_cell_limine_kernel_plan[32] __attribute__((section(".bss.silt"), aligned(8)));' "$TMPDIR/limine.c"; then
  echo "generated Limine entry does not emit the typed kernel plan static cell in bss" >&2
  exit 1
fi

if ! grep -Fq 'static uint8_t silt_cell_limine_kernel_plan_invariant[24] __attribute__((section(".bss.silt"), aligned(8)));' "$TMPDIR/limine.c"; then
  echo "generated Limine entry does not emit the typed kernel plan-invariant static cell in bss" >&2
  exit 1
fi

if ! grep -Fq 'static uint8_t silt_cell_limine_kernel_frame_candidate[40] __attribute__((section(".bss.silt"), aligned(8)));' "$TMPDIR/limine.c"; then
  echo "generated Limine entry does not emit the typed kernel frame-candidate static cell in bss" >&2
  exit 1
fi

if ! grep -Fq 'static uint8_t silt_cell_limine_kernel_frame_eligibility[48] __attribute__((section(".bss.silt"), aligned(8)));' "$TMPDIR/limine.c"; then
  echo "generated Limine entry does not emit the typed kernel frame-eligibility static cell in bss" >&2
  exit 1
fi

if ! grep -Fq 'static uint8_t silt_cell_limine_kernel_frame_reservation_intent[56] __attribute__((section(".bss.silt"), aligned(8)));' "$TMPDIR/limine.c"; then
  echo "generated Limine entry does not emit the typed kernel frame-reservation-intent static cell in bss" >&2
  exit 1
fi

if ! grep -Fq 'static uint8_t silt_cell_limine_kernel_frame_reservation_invariant[48] __attribute__((section(".bss.silt"), aligned(8)));' "$TMPDIR/limine.c"; then
  echo "generated Limine entry does not emit the typed kernel frame-reservation-invariant static cell in bss" >&2
  exit 1
fi

if ! grep -Fq 'static uint8_t silt_cell_limine_kernel_frame_reservation_state[64] __attribute__((section(".bss.silt"), aligned(8)));' "$TMPDIR/limine.c"; then
  echo "generated Limine entry does not emit the typed kernel frame-reservation-state static cell in bss" >&2
  exit 1
fi

if ! grep -Fq 'static uint8_t silt_cell_limine_kernel_frame_free_list_seed[64] __attribute__((section(".bss.silt"), aligned(8)));' "$TMPDIR/limine.c"; then
  echo "generated Limine entry does not emit the typed kernel frame free-list seed static cell in bss" >&2
  exit 1
fi

if ! grep -Fq 'static uint8_t silt_cell_limine_kernel_frame_alloc_one_state[64] __attribute__((section(".bss.silt"), aligned(8)));' "$TMPDIR/limine.c"; then
  echo "generated Limine entry does not emit the typed kernel frame alloc-one static cell in bss" >&2
  exit 1
fi

if ! grep -Fq 'static uint8_t silt_cell_limine_kernel_frame_free_one_state[64] __attribute__((section(".bss.silt"), aligned(8)));' "$TMPDIR/limine.c"; then
  echo "generated Limine entry does not emit the typed kernel frame free-one static cell in bss" >&2
  exit 1
fi

if ! grep -Fq 'static silt_layout_BootState silt_value_limine_boot_manifest __attribute__((used, section(".data.silt"), aligned(8))) = {{1u, 0u, 0u, 0u, 0u, 0u, 0u, 0u, 66u, 0u, 0u, 0u, 0u, 0u, 0u, 0u}};' "$TMPDIR/limine.c"; then
  echo "generated Limine entry does not emit the typed boot manifest as initialized data" >&2
  exit 1
fi

if ! grep -Fq 'silt_value_limine_requests_start __attribute__((used, section(".limine_requests_start"), aligned(8)))' "$TMPDIR/limine.c"; then
  echo "generated Limine entry does not emit the request start marker section" >&2
  exit 1
fi

if ! grep -Fq 'silt_value_limine_base_revision __attribute__((used, section(".limine_requests"), aligned(8)))' "$TMPDIR/limine.c"; then
  echo "generated Limine entry does not emit the base revision request section" >&2
  exit 1
fi

if ! grep -Fq 'silt_value_limine_hhdm_request __attribute__((used, section(".limine_requests"), aligned(8)))' "$TMPDIR/limine.c"; then
  echo "generated Limine entry does not emit the HHDM request section" >&2
  exit 1
fi

if ! grep -Fq 'silt_value_limine_memmap_request __attribute__((used, section(".limine_requests"), aligned(8)))' "$TMPDIR/limine.c"; then
  echo "generated Limine entry does not emit the Memmap request section" >&2
  exit 1
fi

if ! grep -Fq 'silt_value_limine_requests_end __attribute__((used, section(".limine_requests_end"), aligned(8)))' "$TMPDIR/limine.c"; then
  echo "generated Limine entry does not emit the request end marker section" >&2
  exit 1
fi

if ! grep -Fq '(*((silt_layout_BootState*)(((uintptr_t)&silt_cell_limine_boot_state[0])))) = BootState_0;' "$TMPDIR/limine.c"; then
  echo "generated Limine entry does not store BootState through the static cell pointer" >&2
  exit 1
fi

if ! grep -Fq 'silt_layout_BootState state_1 = (*((silt_layout_BootState*)(((uintptr_t)&silt_cell_limine_boot_state[0]))));' "$TMPDIR/limine.c"; then
  echo "generated Limine entry does not load BootState back through the static cell pointer" >&2
  exit 1
fi

if ! grep -Fq 'silt_layout_BootState manifest_2 = (*((silt_layout_BootState*)(((uintptr_t)&silt_value_limine_boot_manifest))));' "$TMPDIR/limine.c"; then
  echo "generated Limine entry does not load the initialized boot manifest" >&2
  exit 1
fi

if ! grep -Fq '(*((silt_layout_BootInfo*)(((uintptr_t)&silt_cell_limine_boot_info[0])))) = BootInfo_' "$TMPDIR/limine.c"; then
  echo "generated Limine entry does not store BootInfo through the static cell pointer" >&2
  exit 1
fi

if ! grep -Fq 'silt_layout_BootInfo info_' "$TMPDIR/limine.c"; then
  echo "generated Limine entry does not load BootInfo back through the static cell pointer" >&2
  exit 1
fi

if ! grep -Fq '(*((silt_layout_KernelBootSpan*)(((uintptr_t)&silt_cell_limine_kernel_span[0])))) = KernelBootSpan_' "$TMPDIR/limine.c"; then
  echo "generated Limine entry does not store KernelBootSpan through the static cell pointer" >&2
  exit 1
fi

if ! grep -Fq 'silt_layout_KernelBootSpan span_' "$TMPDIR/limine.c"; then
  echo "generated Limine entry does not load KernelBootSpan back through the static cell pointer" >&2
  exit 1
fi

if ! grep -Fq '(*((uint64_t*)(((uintptr_t)&silt_cell_limine_kernel_page_count[0])))) =' "$TMPDIR/limine.c"; then
  echo "generated Limine entry does not store the kernel page count through the static cell pointer" >&2
  exit 1
fi

if ! grep -Fq 'uint64_t page_count_' "$TMPDIR/limine.c"; then
  echo "generated Limine entry does not load the kernel page count back through the static cell pointer" >&2
  exit 1
fi

if ! grep -Fq '(*((silt_layout_KernelBootPolicy*)(((uintptr_t)&silt_cell_limine_kernel_policy[0])))) =' "$TMPDIR/limine.c"; then
  echo "generated Limine entry does not store KernelBootPolicy through the static cell pointer" >&2
  exit 1
fi

if ! grep -Fq 'silt_layout_KernelBootPolicy policy_' "$TMPDIR/limine.c"; then
  echo "generated Limine entry does not load KernelBootPolicy back through the static cell pointer" >&2
  exit 1
fi

if ! grep -Fq '(*((silt_layout_KernelBootPlan*)(((uintptr_t)&silt_cell_limine_kernel_plan[0])))) =' "$TMPDIR/limine.c"; then
  echo "generated Limine entry does not store KernelBootPlan through the static cell pointer" >&2
  exit 1
fi

if ! grep -Fq 'silt_layout_KernelBootPlan plan_' "$TMPDIR/limine.c"; then
  echo "generated Limine entry does not load KernelBootPlan back through the static cell pointer" >&2
  exit 1
fi

if ! grep -Fq '(*((silt_layout_KernelBootPlanInvariant*)(((uintptr_t)&silt_cell_limine_kernel_plan_invariant[0])))) =' "$TMPDIR/limine.c"; then
  echo "generated Limine entry does not store KernelBootPlanInvariant through the static cell pointer" >&2
  exit 1
fi

if ! grep -Fq 'silt_layout_KernelBootPlanInvariant invariant_' "$TMPDIR/limine.c"; then
  echo "generated Limine entry does not load KernelBootPlanInvariant back through the static cell pointer" >&2
  exit 1
fi

if ! grep -Fq '(*((silt_layout_KernelFrameCandidate*)(((uintptr_t)&silt_cell_limine_kernel_frame_candidate[0])))) =' "$TMPDIR/limine.c"; then
  echo "generated Limine entry does not store KernelFrameCandidate through the static cell pointer" >&2
  exit 1
fi

if ! grep -Fq 'silt_layout_KernelFrameCandidate candidate_' "$TMPDIR/limine.c"; then
  echo "generated Limine entry does not load KernelFrameCandidate back through the static cell pointer" >&2
  exit 1
fi

if ! grep -Fq '(*((silt_layout_KernelFrameEligibility*)(((uintptr_t)&silt_cell_limine_kernel_frame_eligibility[0])))) =' "$TMPDIR/limine.c"; then
  echo "generated Limine entry does not store KernelFrameEligibility through the static cell pointer" >&2
  exit 1
fi

if ! grep -Fq 'silt_layout_KernelFrameEligibility eligibility_' "$TMPDIR/limine.c"; then
  echo "generated Limine entry does not load KernelFrameEligibility back through the static cell pointer" >&2
  exit 1
fi

if ! grep -Fq '(*((silt_layout_KernelFrameReservationIntent*)(((uintptr_t)&silt_cell_limine_kernel_frame_reservation_intent[0])))) =' "$TMPDIR/limine.c"; then
  echo "generated Limine entry does not store KernelFrameReservationIntent through the static cell pointer" >&2
  exit 1
fi

if ! grep -Fq 'silt_layout_KernelFrameReservationIntent intent_' "$TMPDIR/limine.c"; then
  echo "generated Limine entry does not load KernelFrameReservationIntent back through the static cell pointer" >&2
  exit 1
fi

if ! grep -Fq '(*((silt_layout_KernelFrameReservationInvariant*)(((uintptr_t)&silt_cell_limine_kernel_frame_reservation_invariant[0])))) =' "$TMPDIR/limine.c"; then
  echo "generated Limine entry does not store KernelFrameReservationInvariant through the static cell pointer" >&2
  exit 1
fi

if ! grep -Fq 'silt_layout_KernelFrameReservationInvariant invariant_' "$TMPDIR/limine.c"; then
  echo "generated Limine entry does not load KernelFrameReservationInvariant back through the static cell pointer" >&2
  exit 1
fi

if ! grep -Fq '(*((silt_layout_KernelFrameReservationState*)(((uintptr_t)&silt_cell_limine_kernel_frame_reservation_state[0])))) =' "$TMPDIR/limine.c"; then
  echo "generated Limine entry does not store KernelFrameReservationState through the static cell pointer" >&2
  exit 1
fi

if ! grep -Fq 'silt_layout_KernelFrameReservationState state_' "$TMPDIR/limine.c"; then
  echo "generated Limine entry does not load KernelFrameReservationState back through the static cell pointer" >&2
  exit 1
fi

if ! grep -Fq '(*((silt_layout_KernelFrameFreeListSeed*)(((uintptr_t)&silt_cell_limine_kernel_frame_free_list_seed[0])))) =' "$TMPDIR/limine.c"; then
  echo "generated Limine entry does not store KernelFrameFreeListSeed through the static cell pointer" >&2
  exit 1
fi

if ! grep -Fq 'silt_layout_KernelFrameFreeListSeed seed_' "$TMPDIR/limine.c"; then
  echo "generated Limine entry does not load KernelFrameFreeListSeed back through the static cell pointer" >&2
  exit 1
fi

if ! grep -Fq '(*((silt_layout_KernelFrameAllocOneState*)(((uintptr_t)&silt_cell_limine_kernel_frame_alloc_one_state[0])))) =' "$TMPDIR/limine.c"; then
  echo "generated Limine entry does not store KernelFrameAllocOneState through the static cell pointer" >&2
  exit 1
fi

if ! grep -Fq 'silt_layout_KernelFrameAllocOneState state_' "$TMPDIR/limine.c"; then
  echo "generated Limine entry does not load KernelFrameAllocOneState back through the static cell pointer" >&2
  exit 1
fi

if ! grep -Fq '(*((silt_layout_KernelFrameFreeOneState*)(((uintptr_t)&silt_cell_limine_kernel_frame_free_one_state[0])))) =' "$TMPDIR/limine.c"; then
  echo "generated Limine entry does not store KernelFrameFreeOneState through the static cell pointer" >&2
  exit 1
fi

if ! grep -Fq 'silt_layout_KernelFrameFreeOneState freed_' "$TMPDIR/limine.c"; then
  echo "generated Limine entry does not load KernelFrameFreeOneState back through the static cell pointer" >&2
  exit 1
fi

if ! grep -Fq 'silt_layout_LimineHhdmRequest request_' "$TMPDIR/limine.c"; then
  echo "generated Limine entry does not load the HHDM request object" >&2
  exit 1
fi

if ! grep -Fq 'silt_layout_LimineHhdmResponse response_' "$TMPDIR/limine.c"; then
  echo "generated Limine entry does not load the HHDM response object" >&2
  exit 1
fi

if ! grep -Fq 'silt_layout_LimineMemmapRequest request_' "$TMPDIR/limine.c"; then
  echo "generated Limine entry does not load the Memmap request object" >&2
  exit 1
fi

if ! grep -Fq 'silt_layout_LimineMemmapResponse response_' "$TMPDIR/limine.c"; then
  echo "generated Limine entry does not load the Memmap response object" >&2
  exit 1
fi

if ! grep -Fq 'uintptr_t first_entry_ptr_' "$TMPDIR/limine.c"; then
  echo "generated Limine entry does not load the Memmap entry pointer" >&2
  exit 1
fi

if ! grep -Fq 'silt_layout_LimineMemmapEntry first_entry_' "$TMPDIR/limine.c"; then
  echo "generated Limine entry does not load the first Memmap entry" >&2
  exit 1
fi

if ! grep -Fq 'silt_static_limine_memmap_ok_bytes[0]' "$TMPDIR/limine.c"; then
  echo "generated Limine entry does not take the Memmap marker pointer from static bytes" >&2
  exit 1
fi

if ! grep -Fq 'silt_static_limine_boot_info_ok_bytes[0]' "$TMPDIR/limine.c"; then
  echo "generated Limine entry does not take the boot-info marker pointer from static bytes" >&2
  exit 1
fi

if ! grep -Fq 'silt_static_limine_boot_span_ok_bytes[0]' "$TMPDIR/limine.c"; then
  echo "generated Limine entry does not take the boot-span marker pointer from static bytes" >&2
  exit 1
fi

if ! grep -Fq 'silt_static_limine_kernel_span_ok_bytes[0]' "$TMPDIR/limine.c"; then
  echo "generated Limine entry does not take the kernel-span marker pointer from static bytes" >&2
  exit 1
fi

if ! grep -Fq 'silt_static_limine_kernel_pages_ok_bytes[0]' "$TMPDIR/limine.c"; then
  echo "generated Limine entry does not take the kernel-pages marker pointer from static bytes" >&2
  exit 1
fi

if ! grep -Fq 'silt_static_limine_boot_policy_ok_bytes[0]' "$TMPDIR/limine.c"; then
  echo "generated Limine entry does not take the boot-policy marker pointer from static bytes" >&2
  exit 1
fi

if ! grep -Fq 'silt_static_limine_boot_plan_ok_bytes[0]' "$TMPDIR/limine.c"; then
  echo "generated Limine entry does not take the boot-plan marker pointer from static bytes" >&2
  exit 1
fi

if ! grep -Fq 'silt_static_limine_plan_invariant_ok_bytes[0]' "$TMPDIR/limine.c"; then
  echo "generated Limine entry does not take the plan-invariant marker pointer from static bytes" >&2
  exit 1
fi

if ! grep -Fq 'silt_static_limine_frame_candidate_ok_bytes[0]' "$TMPDIR/limine.c"; then
  echo "generated Limine entry does not take the frame-candidate marker pointer from static bytes" >&2
  exit 1
fi

if ! grep -Fq 'silt_static_limine_frame_eligibility_ok_bytes[0]' "$TMPDIR/limine.c"; then
  echo "generated Limine entry does not take the frame-eligibility marker pointer from static bytes" >&2
  exit 1
fi

if ! grep -Fq 'silt_static_limine_frame_reservation_ok_bytes[0]' "$TMPDIR/limine.c"; then
  echo "generated Limine entry does not take the frame-reservation marker pointer from static bytes" >&2
  exit 1
fi

if ! grep -Fq 'silt_static_limine_frame_reservation_invariant_ok_bytes[0]' "$TMPDIR/limine.c"; then
  echo "generated Limine entry does not take the frame-reservation-invariant marker pointer from static bytes" >&2
  exit 1
fi

if ! grep -Fq 'silt_static_limine_frame_reservation_state_ok_bytes[0]' "$TMPDIR/limine.c"; then
  echo "generated Limine entry does not take the frame-reservation-state marker pointer from static bytes" >&2
  exit 1
fi

if ! grep -Fq 'silt_static_limine_frame_free_list_seed_ok_bytes[0]' "$TMPDIR/limine.c"; then
  echo "generated Limine entry does not take the frame free-list seed marker pointer from static bytes" >&2
  exit 1
fi

if ! grep -Fq 'silt_static_limine_frame_alloc_one_ok_bytes[0]' "$TMPDIR/limine.c"; then
  echo "generated Limine entry does not take the frame alloc-one marker pointer from static bytes" >&2
  exit 1
fi

if ! grep -Fq 'silt_static_limine_frame_free_one_ok_bytes[0]' "$TMPDIR/limine.c"; then
  echo "generated Limine entry does not take the frame free-one marker pointer from static bytes" >&2
  exit 1
fi

if ! grep -Fq 'silt_static_limine_ok_bytes[0]' "$TMPDIR/limine.c"; then
  echo "generated Limine entry does not take the success message pointer from static bytes" >&2
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

if ! grep -Fq 'uint8_t serial_write_slice20(silt_layout_SerialSlice slice) {' "$TMPDIR/messages.c"; then
  echo "generated serial byte-slice writer does not take a SerialSlice layout value" >&2
  exit 1
fi

if ! grep -Fq '== 20ULL' "$TMPDIR/messages.c"; then
  echo "generated serial byte-slice writer does not guard the fixed 20-byte length" >&2
  exit 1
fi

if ! grep -Fq 'uint8_t byte_2 = (*((uint8_t*)' "$TMPDIR/messages.c"; then
  echo "generated serial byte-slice writer does not load U8 bytes through the base pointer" >&2
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

if ! nm "$TMPDIR/messages.o" | awk '$2 == "T" && $3 == "serial_write_slice20" { found = 1 } END { exit found ? 0 : 1 }'; then
  echo "message writer object is missing serial_write_slice20" >&2
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

if ! objdump -h "$TMPDIR/silt-limine.elf" | awk '$2 == ".rodata" { found = 1 } END { exit found ? 0 : 1 }'; then
  echo "Limine kernel artifact is missing a rodata section for static bytes" >&2
  exit 1
fi

if ! objdump -h "$TMPDIR/silt-limine.elf" | awk '$2 == ".bss" { found = 1 } END { exit found ? 0 : 1 }'; then
  echo "Limine kernel artifact is missing a bss section for static cells" >&2
  exit 1
fi

if ! objdump -h "$TMPDIR/silt-limine.elf" | awk '$2 == ".limine_requests_start" { found = 1 } END { exit found ? 0 : 1 }'; then
  echo "Limine kernel artifact is missing the request start marker section" >&2
  exit 1
fi

if ! objdump -h "$TMPDIR/silt-limine.elf" | awk '$2 == ".limine_requests" { found = 1 } END { exit found ? 0 : 1 }'; then
  echo "Limine kernel artifact is missing the request section" >&2
  exit 1
fi

if ! objdump -h "$TMPDIR/silt-limine.elf" | awk '$2 == ".limine_requests_end" { found = 1 } END { exit found ? 0 : 1 }'; then
  echo "Limine kernel artifact is missing the request end marker section" >&2
  exit 1
fi

if ! nm "$TMPDIR/silt-limine.elf" | grep -Fq 'silt_cell_limine_boot_state'; then
  echo "Limine kernel artifact is missing the boot-state static cell symbol" >&2
  exit 1
fi

if ! nm "$TMPDIR/silt-limine.elf" | grep -Fq 'silt_cell_limine_boot_info'; then
  echo "Limine kernel artifact is missing the boot-info static cell symbol" >&2
  exit 1
fi

if ! nm "$TMPDIR/silt-limine.elf" | grep -Fq 'silt_value_limine_boot_manifest'; then
  echo "Limine kernel artifact is missing the initialized boot manifest symbol" >&2
  exit 1
fi

if ! nm "$TMPDIR/silt-limine.elf" | grep -Fq 'silt_value_limine_hhdm_request'; then
  echo "Limine kernel artifact is missing the HHDM request symbol" >&2
  exit 1
fi

if ! nm "$TMPDIR/silt-limine.elf" | grep -Fq 'silt_value_limine_memmap_request'; then
  echo "Limine kernel artifact is missing the Memmap request symbol" >&2
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
