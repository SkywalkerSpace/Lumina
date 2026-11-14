#!/usr/bin/env bash
# Protocol tests need only Command Line Tools, not Lumina's submodules/CMake.
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
if [[ $# -gt 1 || ( $# -eq 1 && "$1" != "--integration" ) ]]; then
    printf 'Usage: bash scripts/test_macos_gamepad.sh [--integration]\n' >&2
    exit 2
fi
build_dir="$(mktemp -d "${TMPDIR:-/tmp}/lumina-gamepad.XXXXXX")"
printf 'Test build directory: %s\n' "$build_dir"
clang -std=c11 -Wall -Wextra -Werror -fsanitize=address,undefined \
    -I "$root/src/platform/macos" "$root/tests/unit/test_macos_dualsense.c" \
    -o "$build_dir/protocol-tests"
"$build_dir/protocol-tests"
# input.mm imports this header as Objective-C++; verify both language modes.
printf '#import "hid_gamepad.h"\n' | clang++ -x objective-c++ -std=c++17 \
    -fblocks -Wall -Wextra -Werror -fsyntax-only -I "$root/src/platform/macos" -
clang -fblocks -Wall -Wextra -Werror -I "$root/src/platform/macos" \
    "$root/src/platform/macos/hid_gamepad.m" \
    "$root/tests/integration/test_macos_dualsense.m" \
    -framework Foundation -framework IOKit -framework GameController \
    -o "$build_dir/integration-tests"
if [[ "${1:-}" == "--integration" ]]; then
    # Only sign the newly built test executable. Never change system policy or
    # re-sign the installed app. Restricted entitlements may be denied locally.
    codesign --force --sign - --entitlements "$root/hid_entitlements.plist" \
        "$build_dir/integration-tests"
    "$build_dir/integration-tests"
else
    printf 'HID implementation and integration test compiled; native runtime test not run.\n'
    printf 'Use --integration to sign/run the isolated virtual-controller test.\n'
fi
