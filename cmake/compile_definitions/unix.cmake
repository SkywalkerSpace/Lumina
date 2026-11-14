# unix specific compile definitions
# put anything here that applies to both linux and macos

list(APPEND SUNSHINE_EXTERNAL_LIBRARIES
        ${CURL_LIBRARIES})

# Development builds on macOS run directly from the build tree. Keep the
# compile-time asset path aligned with the assets generated in that directory.
if(APPLE AND NOT SUNSHINE_PACKAGE_MACOS AND NOT SUNSHINE_BUILD_HOMEBREW)
    set(SUNSHINE_ASSETS_DIR "${CMAKE_BINARY_DIR}/${SUNSHINE_ASSETS_DIR}")
# Installed builds resolve relative asset paths against the install prefix.
elseif(NOT SUNSHINE_PACKAGE_MACOS AND NOT SUNSHINE_ASSETS_DIR MATCHES "^${CMAKE_INSTALL_PREFIX}" AND NOT SUNSHINE_ASSETS_DIR MATCHES "^/")
    set(SUNSHINE_ASSETS_DIR "${CMAKE_INSTALL_PREFIX}/${SUNSHINE_ASSETS_DIR}")
endif()
