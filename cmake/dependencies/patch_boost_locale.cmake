# Boost 1.89.0 includes boost/locale.hpp in its header list, but its source_group
# tree only covers boost/locale/. Use their common parent so CMake accepts both.
set(locale_cmake "${BOOST_SOURCE_DIR}/libs/locale/CMakeLists.txt")
file(READ "${locale_cmake}" contents)
set(original [=[source_group(TREE "${CMAKE_CURRENT_SOURCE_DIR}/include/boost/locale" PREFIX "headers" FILES ${sources_inc})]=])
set(patched [=[source_group(TREE "${CMAKE_CURRENT_SOURCE_DIR}/include/boost" PREFIX "headers" FILES ${sources_inc})]=])

string(FIND "${contents}" "${original}" original_position)
if(NOT original_position EQUAL -1)
    string(REPLACE "${original}" "${patched}" contents "${contents}")
    file(WRITE "${locale_cmake}" "${contents}")
else()
    # FetchContent can run the patch again when reconfiguring an existing build.
    string(FIND "${contents}" "${patched}" patched_position)
    if(patched_position EQUAL -1)
        message(FATAL_ERROR "Cannot apply Boost.Locale source_group fix: unexpected CMakeLists.txt")
    endif()
endif()
