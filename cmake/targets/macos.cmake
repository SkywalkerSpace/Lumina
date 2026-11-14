# macos specific target definitions
target_link_options(sunshine PRIVATE LINKER:-sectcreate,__TEXT,__info_plist,${APPLE_PLIST_FILE})
# Tell linker to dynamically load these symbols at runtime, in case they're unavailable:
target_link_options(sunshine PRIVATE -Wl,-U,_CGPreflightScreenCaptureAccess -Wl,-U,_CGRequestScreenCaptureAccess)

# A qt.conf beside the executable overrides Qt's compiled-in plugin path. For
# local development builds, point it at the Qt installation used by CMake.
if(SUNSHINE_ENABLE_TRAY AND NOT SUNSHINE_PACKAGE_MACOS)
    get_filename_component(LUMINA_QT_PREFIX "${Qt6_DIR}/../../.." ABSOLUTE)
    file(WRITE "${CMAKE_BINARY_DIR}/qt.conf"
            "[Paths]\nPlugins = ${LUMINA_QT_PREFIX}/share/qt/plugins\n")
endif()
