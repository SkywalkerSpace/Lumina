/**
 * @file src/platform/macos/misc.h
 * @brief Miscellaneous declarations for macOS platform.
 */
#pragma once

// standard includes
#include <vector>

// platform includes
#include <CoreGraphics/CoreGraphics.h>

namespace platf {
  bool is_screen_capture_allowed();

  /** @brief Read the saved preference for hiding Lumina's Dock icon. */
  bool dock_icon_hidden();

  /** @brief Apply Dock visibility without saving. Call on the main thread after tray initialization. */
  bool apply_dock_icon_hidden(bool hidden);

  /** @brief Apply Dock visibility and save it if changed. Same thread requirements as apply_dock_icon_hidden(). */
  bool set_dock_icon_hidden(bool hidden);
}  // namespace platf

namespace dyn {
  typedef void (*apiproc)();

  int load(void *handle, const std::vector<std::tuple<apiproc *, const char *>> &funcs, bool strict = true);
  void *handle(const std::vector<const char *> &libs);

}  // namespace dyn
