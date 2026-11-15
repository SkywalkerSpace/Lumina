#!/usr/bin/env bash
# Read-only diagnostics for an already-running Lumina DualSense controller.
# Requires Command Line Tools. Never signs code or changes system policy.
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
mode=background
case "${1:-}" in
    "") ;;
    --foreground) mode=foreground ;;
    --compile-only) mode=compile ;;
    *) printf 'Usage: bash scripts/diagnose_macos_gamepad.sh [--foreground|--compile-only]\n' >&2; exit 2 ;;
esac
if [[ $# -gt 1 ]]; then
    printf 'Pass at most one option.\n' >&2
    exit 2
fi
build_dir="$(mktemp -d "${TMPDIR:-/tmp}/lumina-hid-probe.XXXXXX")"
trap 'rm -rf -- "$build_dir"' EXIT
clang -fobjc-arc -fblocks -Wall -Wextra -Werror \
    "$root/tools/macos_gamepad_probe.m" \
    -framework Foundation -framework AppKit -framework IOKit -framework GameController \
    -o "$build_dir/macos-gamepad-probe"
if [[ "$mode" == compile ]]; then
    printf 'Read-only HID/GameController probe compiled. Runtime capture was not run.\n'
elif [[ "$mode" == foreground ]]; then
    "$build_dir/macos-gamepad-probe" --foreground
else
    "$build_dir/macos-gamepad-probe"
fi
