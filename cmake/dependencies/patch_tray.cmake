# Keep Lumina's menu-only update API in a parent-repository patch rather than
# depending on an unpublished tray submodule commit.
find_package(Git REQUIRED)
set(TRAY_SOURCE_DIR "${CMAKE_CURRENT_LIST_DIR}/../../third-party/tray")
set(TRAY_PATCH "${CMAKE_CURRENT_LIST_DIR}/../../third-party/tray.diff")

# Reconfiguration must also work when the patch has already been applied.
execute_process(
        COMMAND "${GIT_EXECUTABLE}" apply --reverse --check "${TRAY_PATCH}"
        WORKING_DIRECTORY "${TRAY_SOURCE_DIR}"
        RESULT_VARIABLE TRAY_PATCH_ALREADY_APPLIED
        OUTPUT_QUIET ERROR_QUIET
)
if(TRAY_PATCH_ALREADY_APPLIED EQUAL 0)
    return()
endif()

# git apply is atomic: incompatible or partially patched sources fail without
# overwriting local changes. Do not continue with a missing or mismatched API.
execute_process(
        COMMAND "${GIT_EXECUTABLE}" apply "${TRAY_PATCH}"
        WORKING_DIRECTORY "${TRAY_SOURCE_DIR}"
        RESULT_VARIABLE TRAY_PATCH_RESULT
        ERROR_VARIABLE TRAY_PATCH_ERROR
)
if(NOT TRAY_PATCH_RESULT EQUAL 0)
    message(FATAL_ERROR "Failed to apply ${TRAY_PATCH}:\n${TRAY_PATCH_ERROR}")
endif()
message(STATUS "Applied Lumina tray menu-only update patch")
