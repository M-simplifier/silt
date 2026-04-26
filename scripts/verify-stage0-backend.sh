#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

cd "$ROOT"

cabal test
cabal build exe:silt
SILT_BIN="$(cabal list-bin exe:silt)"

CAPABILITIES_CHECK="$("$SILT_BIN" check examples/capabilities.silt)"
if [[ "$CAPABILITIES_CHECK" != *"rewrite-owned-word-handle :"* ]]; then
  echo "missing rewrite-owned-word-handle in capabilities check output" >&2
  exit 1
fi
if [[ "$CAPABILITIES_CHECK" != *"rewrite-owned-word-cap :"* ]]; then
  echo "missing rewrite-owned-word-cap in capabilities check output" >&2
  exit 1
fi
if [[ "$CAPABILITIES_CHECK" != *"rewrite-owned-word-cap-step :"* ]]; then
  echo "missing rewrite-owned-word-cap-step in capabilities check output" >&2
  exit 1
fi
if [[ "$CAPABILITIES_CHECK" != *"store-owned-cap-step :"* ]]; then
  echo "missing store-owned-cap-step in capabilities check output" >&2
  exit 1
fi
if [[ "$CAPABILITIES_CHECK" != *"read-after-cap-step :"* ]]; then
  echo "missing read-after-cap-step in capabilities check output" >&2
  exit 1
fi
if [[ "$CAPABILITIES_CHECK" != *"rewrite-owned-cap-step :"* ]]; then
  echo "missing rewrite-owned-cap-step in capabilities check output" >&2
  exit 1
fi
if [[ "$CAPABILITIES_CHECK" != *"rewrite-owned-header-next-handle :"* ]]; then
  echo "missing rewrite-owned-header-next-handle in capabilities check output" >&2
  exit 1
fi
if [[ "$CAPABILITIES_CHECK" != *"rewrite-owned-header-next-cap :"* ]]; then
  echo "missing rewrite-owned-header-next-cap in capabilities check output" >&2
  exit 1
fi
if [[ "$CAPABILITIES_CHECK" != *"rewrite-owned-header-next-cap-step :"* ]]; then
  echo "missing rewrite-owned-header-next-cap-step in capabilities check output" >&2
  exit 1
fi
if [[ "$CAPABILITIES_CHECK" != *"rewrite-owned-header-next-cap-value-step :"* ]]; then
  echo "missing rewrite-owned-header-next-cap-value-step in capabilities check output" >&2
  exit 1
fi
OBSERVED_SAMPLE_VALUE="$("$SILT_BIN" norm examples/capabilities.silt observed-sample-value)"
RESTORED_WORD_HANDLE="$("$SILT_BIN" norm examples/capabilities.silt restored-word-handle)"
INCREMENTED_SAMPLE_WORD="$("$SILT_BIN" norm examples/capabilities.silt incremented-sample-word)"
ADVANCED_SAMPLE_NEXT="$("$SILT_BIN" norm examples/capabilities.silt advanced-sample-next)"
REPLACED_HEADER_NEXT_SAMPLE="$("$SILT_BIN" norm examples/capabilities.silt replaced-header-next-sample)"
FORGOT_WORD_CAP_HANDLE="$("$SILT_BIN" norm examples/capabilities.silt forgot-word-cap-handle)"
FORGOT_WORD_CAP_OBSERVED="$("$SILT_BIN" norm examples/capabilities.silt forgot-word-cap-observed)"
FORGOT_HEADER_CAP_HANDLE="$("$SILT_BIN" norm examples/capabilities.silt forgot-header-cap-handle)"
SETTLED_WORD_CAP_STEP="$("$SILT_BIN" norm examples/capabilities.silt settled-word-cap-step)"
FORGOT_WORD_CAP_STEP="$("$SILT_BIN" norm examples/capabilities.silt forgot-word-cap-step)"
SETTLED_HEADER_CAP_STEP="$("$SILT_BIN" norm examples/capabilities.silt settled-header-cap-step)"
FORGOT_HEADER_CAP_STEP="$("$SILT_BIN" norm examples/capabilities.silt forgot-header-cap-step)"
if [[ "$OBSERVED_SAMPLE_VALUE" != "(u64 77)" ]]; then
  echo "unexpected observed-sample-value normalization: $OBSERVED_SAMPLE_VALUE" >&2
  exit 1
fi
if [[ "$RESTORED_WORD_HANDLE" != "((((OwnedAt Lease1) U64) lease1) ((ptr-from-addr U64) (addr 4096)))" ]]; then
  echo "unexpected restored-word-handle normalization: $RESTORED_WORD_HANDLE" >&2
  exit 1
fi
if [[ "$INCREMENTED_SAMPLE_WORD" != "(u64 8)" ]]; then
  echo "unexpected incremented-sample-word normalization: $INCREMENTED_SAMPLE_WORD" >&2
  exit 1
fi
if [[ "$ADVANCED_SAMPLE_NEXT" != "(addr 8192)" ]]; then
  echo "unexpected advanced-sample-next normalization: $ADVANCED_SAMPLE_NEXT" >&2
  exit 1
fi
if [[ "$REPLACED_HEADER_NEXT_SAMPLE" != "(addr 12288)" ]]; then
  echo "unexpected replaced-header-next-sample normalization: $REPLACED_HEADER_NEXT_SAMPLE" >&2
  exit 1
fi
if [[ "$FORGOT_WORD_CAP_HANDLE" != "((((OwnedAt Lease1) U64) lease1) ((ptr-from-addr U64) (addr 4096)))" ]]; then
  echo "unexpected forgot-word-cap-handle normalization: $FORGOT_WORD_CAP_HANDLE" >&2
  exit 1
fi
if [[ "$FORGOT_WORD_CAP_OBSERVED" != "((((((ObservedAt Lease1) U64) U64) lease1) ((ptr-from-addr U64) (addr 4096))) (u64 33))" ]]; then
  echo "unexpected forgot-word-cap-observed normalization: $FORGOT_WORD_CAP_OBSERVED" >&2
  exit 1
fi
if [[ "$FORGOT_HEADER_CAP_HANDLE" != "((((OwnedAt HeaderLease1) Header) header-lease1) ((ptr-from-addr Header) (addr 8192)))" ]]; then
  echo "unexpected forgot-header-cap-handle normalization: $FORGOT_HEADER_CAP_HANDLE" >&2
  exit 1
fi
if [[ "$SETTLED_WORD_CAP_STEP" != "(((((OwnedCapAt Lease1) WordSlot1) U64) lease1) ((ptr-from-addr U64) (addr 4096)))" ]]; then
  echo "unexpected settled-word-cap-step normalization: $SETTLED_WORD_CAP_STEP" >&2
  exit 1
fi
if [[ "$FORGOT_WORD_CAP_STEP" != "((((OwnedAt Lease1) U64) lease1) ((ptr-from-addr U64) (addr 4096)))" ]]; then
  echo "unexpected forgot-word-cap-step normalization: $FORGOT_WORD_CAP_STEP" >&2
  exit 1
fi
if [[ "$SETTLED_HEADER_CAP_STEP" != "(((((OwnedCapAt HeaderLease1) HeaderRegion1) Header) header-lease1) ((ptr-from-addr Header) (addr 8192)))" ]]; then
  echo "unexpected settled-header-cap-step normalization: $SETTLED_HEADER_CAP_STEP" >&2
  exit 1
fi
if [[ "$FORGOT_HEADER_CAP_STEP" != "((((OwnedAt HeaderLease1) Header) header-lease1) ((ptr-from-addr Header) (addr 8192)))" ]]; then
  echo "unexpected forgot-header-cap-step normalization: $FORGOT_HEADER_CAP_STEP" >&2
  exit 1
fi

"$SILT_BIN" emit-c-bundle examples/stage1.silt add pred erase-first word-inc bump-addr bump-ptr step-ptr step-header page-align-down align-up page-count u64-size u64-align > "$TMPDIR/runtime.c"
"$SILT_BIN" emit-c-bundle examples/extern.silt call-host-add3 call-host-bump > "$TMPDIR/extern_runtime.c"
"$SILT_BIN" emit-c-bundle examples/memory.silt read-word write-word seed-word-token seed-and-read-token increment-word bump-and-read read-next write-next read-header-magic read-header-next read-header-next-via-layout read-header-next-via-layout-token write-header-next write-header-next-token read-header-next-token write-header-fields write-header-fields-token override-header-next copy-header > "$TMPDIR/memory_runtime.c"
"$SILT_BIN" emit-c-bundle examples/abi.silt inspect-header call-header-zero > "$TMPDIR/abi_runtime.c"
"$SILT_BIN" emit-c-bundle examples/layout-values.silt header-template header-template-magic header-template-next header-magic-from-arg retarget-header retarget-template-next retargeted-magic-from-arg repack-header repacked-template-magic repacked-template-next override-template-next let-layout-next let-layout-magic-from-arg store-header-template store-and-read-magic > "$TMPDIR/layout_values_runtime.c"

cat > "$TMPDIR/extern_impl.c" <<'EOF'
#include <stdint.h>

uint64_t host_add3(uint64_t x) {
  return x + 3ULL;
}

uintptr_t host_bump(uintptr_t base, uint64_t bytes) {
  return (uintptr_t)(base + bytes + 7ULL);
}
EOF

cat > "$TMPDIR/abi_impl.c" <<'EOF'
#include <stdint.h>

typedef struct {
  _Alignas(8) uint8_t bytes[16];
} silt_layout_Header;

uint64_t header_magic(silt_layout_Header hdr) {
  return (*((const uint64_t *)(const void *)(hdr.bytes + 0)));
}

uint8_t header_zero(uintptr_t ptr) {
  silt_layout_Header zero = {0};
  (*((silt_layout_Header *)(void *)ptr)) = zero;
  return 0u;
}
EOF

cat > "$TMPDIR/main.c" <<'EOF'
#include <stdint.h>
typedef struct {
  _Alignas(8) uint8_t bytes[16];
} silt_layout_Header;
uint64_t add(uint64_t a, uint64_t b);
uint64_t pred(uint64_t n);
uint64_t erase_first(uint64_t x);
uint64_t word_inc(uint64_t x);
uintptr_t bump_addr(uintptr_t base, uint64_t bytes);
uintptr_t bump_ptr(uintptr_t base, uint64_t bytes);
uintptr_t step_ptr(uintptr_t base, uint64_t count);
uintptr_t step_header(uintptr_t base, uint64_t count);
uint64_t page_align_down(uint64_t x);
uint64_t align_up(uint64_t x, uint64_t align);
uint64_t page_count(uint64_t bytes);
uint64_t u64_size(void);
uint64_t u64_align(void);
uint64_t call_host_add3(uint64_t x);
uintptr_t call_host_bump(uintptr_t base, uint64_t bytes);
uint64_t read_word(uintptr_t ptr);
uint8_t write_word(uintptr_t ptr, uint64_t value);
uint8_t seed_word_token(uintptr_t ptr, uint64_t value);
uint64_t seed_and_read_token(uintptr_t ptr, uint64_t value);
uint64_t increment_word(uintptr_t ptr);
uint64_t bump_and_read(uintptr_t base);
uintptr_t read_next(uintptr_t ptr);
uint8_t write_next(uintptr_t ptr, uintptr_t value);
uint64_t read_header_magic(uintptr_t hdr);
uintptr_t read_header_next(uintptr_t hdr);
uintptr_t read_header_next_via_layout(uintptr_t hdr);
uintptr_t read_header_next_via_layout_token(uintptr_t hdr);
uint8_t write_header_next(uintptr_t hdr, uintptr_t value);
uint8_t write_header_next_token(uintptr_t hdr, uintptr_t value);
uintptr_t read_header_next_token(uintptr_t hdr);
uint8_t write_header_fields(uintptr_t hdr, uint64_t magic, uintptr_t next_addr);
uint8_t write_header_fields_token(uintptr_t hdr, uint64_t magic, uintptr_t next_addr);
uint8_t override_header_next(uintptr_t hdr);
uint8_t copy_header(uintptr_t src, uintptr_t dst);
uint64_t inspect_header(uintptr_t ptr);
uint8_t call_header_zero(uintptr_t ptr);
silt_layout_Header header_template(void);
uint64_t header_template_magic(void);
uintptr_t header_template_next(void);
uint64_t header_magic_from_arg(silt_layout_Header hdr);
silt_layout_Header retarget_header(silt_layout_Header hdr, uintptr_t next_addr);
uintptr_t retarget_template_next(void);
uint64_t retargeted_magic_from_arg(silt_layout_Header hdr, uintptr_t next_addr);
silt_layout_Header repack_header(silt_layout_Header hdr, uint64_t magic, uintptr_t next_addr);
uint64_t repacked_template_magic(void);
uintptr_t repacked_template_next(void);
uintptr_t override_template_next(void);
uintptr_t let_layout_next(void);
uint64_t let_layout_magic_from_arg(silt_layout_Header hdr);
uint8_t store_header_template(uintptr_t dst);
uint64_t store_and_read_magic(uintptr_t dst);
int main(void) {
  uint64_t cell = 41ULL;
  uint64_t pair[2] = {7ULL, 11ULL};
  uintptr_t next = (uintptr_t)4096ULL;
  silt_layout_Header src = {0};
  silt_layout_Header dst = {0};
  silt_layout_Header templ = {0};
  (*((uint64_t *)(void *)(src.bytes + 0))) = 77ULL;
  (*((uintptr_t *)(void *)(src.bytes + 8))) = (uintptr_t)4096ULL;
  if (add(2, 1) != 3ULL) return 1;
  if (pred(0) != 0ULL) return 2;
  if (pred(5) != 4ULL) return 3;
  if (erase_first(42) != 42ULL) return 4;
  if (word_inc(41) != 42ULL) return 5;
  if (bump_addr((uintptr_t)4096ULL, 64ULL) != (uintptr_t)4160ULL) return 6;
  if (bump_ptr((uintptr_t)4096ULL, 8ULL) != (uintptr_t)4104ULL) return 7;
  if (step_ptr((uintptr_t)4096ULL, 1ULL) != (uintptr_t)4104ULL) return 8;
  if (step_header((uintptr_t)8192ULL, 2ULL) != (uintptr_t)8224ULL) return 9;
  if (page_align_down(8201ULL) != 8192ULL) return 10;
  if (align_up(4105ULL, 4096ULL) != 8192ULL) return 11;
  if (page_count(5000ULL) != 2ULL) return 12;
  if (u64_size() != 8ULL) return 13;
  if (u64_align() != 8ULL) return 14;
  if (call_host_add3(39ULL) != 42ULL) return 15;
  if (call_host_bump((uintptr_t)4096ULL, 64ULL) != (uintptr_t)4167ULL) return 16;
  if (read_word((uintptr_t)&cell) != 41ULL) return 17;
  if (write_word((uintptr_t)&cell, 99ULL) != 0u) return 18;
  if (cell != 99ULL) return 19;
  if (seed_word_token((uintptr_t)&cell, 123ULL) != 0u) return 20;
  if (cell != 123ULL) return 21;
  if (seed_and_read_token((uintptr_t)&cell, 144ULL) != 144ULL) return 22;
  if (cell != 144ULL) return 23;
  if (increment_word((uintptr_t)&cell) != 145ULL) return 24;
  if (cell != 145ULL) return 25;
  if (bump_and_read((uintptr_t)&pair[0]) != 11ULL) return 26;
  if (read_next((uintptr_t)&next) != (uintptr_t)4096ULL) return 27;
  if (write_next((uintptr_t)&next, (uintptr_t)8192ULL) != 0u) return 28;
  if (next != (uintptr_t)8192ULL) return 29;
  if (read_header_magic((uintptr_t)&src) != 77ULL) return 30;
  if (read_header_next((uintptr_t)&src) != (uintptr_t)4096ULL) return 31;
  if (read_header_next_via_layout((uintptr_t)&src) != (uintptr_t)4096ULL) return 32;
  if (write_header_next((uintptr_t)&src, (uintptr_t)12288ULL) != 0u) return 33;
  if (read_header_next((uintptr_t)&src) != (uintptr_t)12288ULL) return 34;
  if (write_header_next_token((uintptr_t)&src, (uintptr_t)20480ULL) != 0u) return 35;
  if (read_header_next_token((uintptr_t)&src) != (uintptr_t)20480ULL) return 36;
  if (read_header_next_via_layout_token((uintptr_t)&src) != (uintptr_t)20480ULL) return 37;
  if (write_header_fields_token((uintptr_t)&src, 66ULL, (uintptr_t)24576ULL) != 0u) return 38;
  if (read_header_magic((uintptr_t)&src) != 66ULL) return 39;
  if (read_header_next((uintptr_t)&src) != (uintptr_t)24576ULL) return 40;
  if (write_header_fields((uintptr_t)&src, 55ULL, (uintptr_t)16384ULL) != 0u) return 41;
  if (read_header_magic((uintptr_t)&src) != 55ULL) return 42;
  if (read_header_next((uintptr_t)&src) != (uintptr_t)16384ULL) return 43;
  if (read_header_next_via_layout((uintptr_t)&src) != (uintptr_t)16384ULL) return 44;
  if (override_header_next((uintptr_t)&src) != 0u) return 45;
  if (read_header_next((uintptr_t)&src) != (uintptr_t)12288ULL) return 46;
  if (copy_header((uintptr_t)&src, (uintptr_t)&dst) != 0u) return 47;
  if (inspect_header((uintptr_t)&dst) != 55ULL) return 48;
  if (call_header_zero((uintptr_t)&dst) != 0u) return 49;
  if (inspect_header((uintptr_t)&dst) != 0ULL) return 50;
  templ = header_template();
  if ((*((uint64_t *)(void *)(templ.bytes + 0))) != 77ULL) return 51;
  if (header_template_magic() != 77ULL) return 52;
  if (header_template_next() != (uintptr_t)4096ULL) return 53;
  if (header_magic_from_arg(templ) != 77ULL) return 54;
  templ = retarget_header(templ, (uintptr_t)8192ULL);
  if ((*((uintptr_t *)(void *)(templ.bytes + 8))) != (uintptr_t)8192ULL) return 55;
  if (retarget_template_next() != (uintptr_t)8192ULL) return 56;
  if (retargeted_magic_from_arg(templ, (uintptr_t)12288ULL) != 77ULL) return 57;
  if (let_layout_next() != (uintptr_t)4096ULL) return 58;
  if (let_layout_magic_from_arg(templ) != 77ULL) return 59;
  templ = repack_header(templ, 99ULL, (uintptr_t)12288ULL);
  if ((*((uint64_t *)(void *)(templ.bytes + 0))) != 99ULL) return 60;
  if ((*((uintptr_t *)(void *)(templ.bytes + 8))) != (uintptr_t)12288ULL) return 61;
  if (repacked_template_magic() != 99ULL) return 62;
  if (repacked_template_next() != (uintptr_t)12288ULL) return 63;
  if (override_template_next() != (uintptr_t)12288ULL) return 64;
  if (store_header_template((uintptr_t)&dst) != 0u) return 65;
  if (inspect_header((uintptr_t)&dst) != 77ULL) return 66;
  if (store_and_read_magic((uintptr_t)&dst) != 77ULL) return 67;
  return 0;
}
EOF

cc -std=c11 -Wall -Wextra -o "$TMPDIR/check" \
  "$TMPDIR/runtime.c" \
  "$TMPDIR/extern_runtime.c" \
  "$TMPDIR/memory_runtime.c" \
  "$TMPDIR/abi_runtime.c" \
  "$TMPDIR/layout_values_runtime.c" \
  "$TMPDIR/extern_impl.c" \
  "$TMPDIR/abi_impl.c" \
  "$TMPDIR/main.c"

"$TMPDIR/check"
