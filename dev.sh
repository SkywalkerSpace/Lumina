#!/bin/bash
set -euo pipefail

# Resolve all build inputs relative to this script, not the caller's directory.
PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD_DIR="$PROJECT_DIR/build"
INSTALL_DIR="$HOME/.local/share/lumina"
cd "$PROJECT_DIR"

lumina_perf_logging=OFF

case "${1:-}" in
  "")
    ;;
  performance)
    lumina_perf_logging=ON
    ;;
  *)
    echo "Usage: $0 [performance]" >&2
    exit 2
    ;;
esac

if [ "$#" -gt 1 ]; then
  echo "Usage: $0 [performance]" >&2
  exit 2
fi

# Use the same relative asset path for the runtime and package. CMake resolves
# it against the install prefix for non-portable Unix builds; the portable
# macOS package keeps it relative to the package root.
cmake -S "$PROJECT_DIR" -B "$BUILD_DIR" \
  -DBUILD_DOCS=OFF \
  -DSUNSHINE_ASSETS_DIR=assets \
  -DSUNSHINE_BUILD_HOMEBREW=OFF \
  -DSUNSHINE_PACKAGE_MACOS=OFF \
  -DCMAKE_PREFIX_PATH="$(brew --prefix qtbase);$(brew --prefix qtsvg)" \
  -DQt6Svg_DIR="$(brew --prefix qtsvg)/lib/cmake/Qt6Svg" \
  -DLUMINA_ENABLE_STREAM_PERF_LOGGING="$lumina_perf_logging"
SUNSHINE_BUILD_HOMEBREW= \
SUNSHINE_SOURCE_ASSETS_DIR="$PROJECT_DIR/src_assets" \
SUNSHINE_ASSETS_DIR="$BUILD_DIR" npm run build-clean
cmake --build "$BUILD_DIR" --target sunshine vd_helper --parallel 4

# Fail before installing if the frontend was not generated successfully.
test -s "$BUILD_DIR/assets/web/index.html"
plutil -lint "$PROJECT_DIR/hid_entitlements.plist"
mkdir -p "$INSTALL_DIR/assets/web"
cp -f build/lumina "$INSTALL_DIR/lumina"
cp -f build/vd_helper "$INSTALL_DIR/vd_helper"
cp -f hid_entitlements.plist "$INSTALL_DIR/hid_entitlements.plist"
cp -Rf build/assets/. "$INSTALL_DIR/assets/"

# Sign for gamepad support only if AMFI is disabled. With AMFI enabled, the
# restricted HID entitlement causes macOS to kill the process on launch.
if nvram boot-args 2>/dev/null | grep -q "amfi_get_out_of_my_way=1"; then
  codesign --sign - --entitlements "$INSTALL_DIR/hid_entitlements.plist" --force "$INSTALL_DIR/lumina"
  codesign --sign - --force "$INSTALL_DIR/vd_helper"
else
  echo "AMFI is enabled — skipping code signing (gamepad support unavailable)."
fi

printf '\nBuild and install complete. Stop any running Lumina instance, then start:\n  "%s/lumina"\nWeb UI: https://localhost:47990\n' "$INSTALL_DIR"
