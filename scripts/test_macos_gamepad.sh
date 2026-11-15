#!/usr/bin/env bash
# Protocol tests need only Command Line Tools, not Lumina's submodules/CMake.
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
mode=compile
profile=auto
for arg in "$@"; do
    case "$arg" in
        --integration|--monitor)
            if [[ "$mode" != compile ]]; then
                printf 'Choose only one of --integration and --monitor.\n' >&2
                exit 2
            fi
            mode="${arg#--}"
            ;;
        --profile=auto|--profile=ds5|--profile=xbox) profile="${arg#--profile=}" ;;
        *)
            printf 'Usage: bash scripts/test_macos_gamepad.sh [--integration|--monitor] [--profile=auto|ds5|xbox]\n' >&2
            exit 2
            ;;
    esac
done
build_dir="$(mktemp -d "${TMPDIR:-/tmp}/lumina-gamepad.XXXXXX")"
printf 'Test build directory: %s\n' "$build_dir"
clang -std=c11 -Wall -Wextra -Werror -fsanitize=address,undefined \
    -I "$root/src/platform/macos" "$root/tests/unit/test_macos_dualsense.c" \
    -o "$build_dir/protocol-tests"
"$build_dir/protocol-tests"
clang -std=c11 -Wall -Wextra -Werror -fsanitize=address,undefined \
    -I "$root/src/platform/macos" "$root/tests/unit/test_macos_xbox.c" \
    -o "$build_dir/xbox-protocol-tests"
"$build_dir/xbox-protocol-tests"
# input.mm imports this header as Objective-C++; verify both language modes.
printf '#import "hid_gamepad.h"\n' | clang++ -x objective-c++ -std=c++17 \
    -fblocks -Wall -Wextra -Werror -fsyntax-only -I "$root/src/platform/macos" -
clang -fblocks -Wall -Wextra -Werror -I "$root/src/platform/macos" \
    "$root/src/platform/macos/hid_gamepad.m" \
    "$root/tests/integration/test_macos_dualsense.m" \
    -framework Foundation -framework AppKit -framework IOKit -framework GameController \
    -o "$build_dir/integration-tests"
if [[ "$mode" == integration ]]; then
    # Only sign the newly built test executable. Never change system policy or
    # re-sign the installed app. Restricted entitlements may be denied locally.
    codesign --force --sign - --entitlements "$root/hid_entitlements.plist" \
        "$build_dir/integration-tests"
    "$build_dir/integration-tests" "--profile=$profile"
elif [[ "$mode" == monitor ]]; then
    # Observe the running app's controller without any restricted signature.
    "$build_dir/integration-tests" --monitor
else
    printf 'HID implementation and integration test compiled; native runtime test not run.\n'
    printf 'Use --integration [--profile=xbox|ds5] to sign/run an isolated controller test.\n'
    printf 'Use --monitor to observe live native input without creating/signing a device.\n'
fi
