#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

require_fixed() {
  local file="$1"
  local needle="$2"
  local label="$3"

  if ! grep -Fq "$needle" "$file"; then
    echo "missing north-star kernel evidence: $label" >&2
    echo "  file: $file" >&2
    echo "  expected fragment: $needle" >&2
    exit 1
  fi
}

require_fixed "examples/limine.silt" "(claim limine-entry (Eff BootIO KernelDone Unit))" "Silt-authored Limine kernel entry"
require_fixed "examples/limine.silt" "(layout BootInfo 40 8" "typed boot handoff object"
require_fixed "examples/limine.silt" "(layout KernelAllocatorHandoff 96 8" "allocator-facing handoff object"
require_fixed "examples/limine.silt" "(layout KernelFrameAllocatorState 104 8" "frame allocator state object"
require_fixed "examples/limine.silt" "(layout KernelFrameLease 88 8" "frame lease object"
require_fixed "examples/limine.silt" "(layout KernelFramePoolLiveState 72 8" "live frame-pool state object"
require_fixed "examples/limine.silt" "(load SerialReady LimineMemmapResponse response-ptr)" "Limine Memmap response load"
require_fixed "examples/limine.silt" "(load SerialReady LimineMemmapEntry first-entry-ptr)" "Limine first memory-map entry load"
require_fixed "examples/limine.silt" "(store SerialReady SerialReady KernelAllocatorHandoff" "typed allocator handoff store"
require_fixed "examples/limine.silt" "(store SerialReady SerialReady KernelFramePoolLiveState" "live frame-pool state update"
require_fixed "examples/limine.silt" "(qemu-debug-exit SerialReady KernelDone (u64 16))" "successful kernel debug-exit"
require_fixed "examples/limine-panic.silt" "(claim kernel-panic-oom (Eff SerialReady (KernelPanicked PanicOom) Unit))" "typed OOM panic path"
require_fixed "examples/limine-panic.silt" "(claim kernel-panic-invariant (Eff SerialReady (KernelPanicked PanicInvariant) Unit))" "typed invariant panic path"
require_fixed "examples/limine-serial.silt" "(claim serial-write-slice20" "serial static-byte output path"
require_fixed "scripts/verify-limine-qemu.sh" "SILT_POOL_LIVE_OK!!" "QEMU-observed live frame-pool marker"
require_fixed "scripts/verify-limine-qemu.sh" "SILT_ALLOC_HANDOFF!" "QEMU-observed allocator handoff marker"
require_fixed "scripts/verify-limine-panic-qemu.sh" "SILT_PANIC" "QEMU-observed panic marker"
require_fixed "STATUS.md" "general allocator" "public allocator non-claim boundary"
require_fixed "STATUS.md" "a complete kernel or OS" "public kernel non-claim"

git diff --check
cabal test all
scripts/verify-stage0-backend.sh
scripts/verify-limine-bridge.sh
scripts/verify-limine-qemu-nix.sh
scripts/verify-limine-panic-qemu-nix.sh
scripts/verify-public.sh

echo "North-star kernel capability verification passed"
