#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

NIX_FLAGS=(--extra-experimental-features "nix-command flakes")
OVMF_STORE="$(nix "${NIX_FLAGS[@]}" eval --raw nixpkgs#OVMF.fd.outPath)"

exec nix "${NIX_FLAGS[@]}" shell \
  nixpkgs#qemu \
  nixpkgs#limine \
  nixpkgs#OVMF.fd \
  --command env OVMF_FD="$OVMF_STORE/FV/OVMF.fd" "$ROOT/scripts/verify-limine-qemu.sh"
