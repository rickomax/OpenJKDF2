set(SYMBOLS_FILE ${PROJECT_SOURCE_DIR}/symbols.syms)
set(GLOBALS_H ${CMAKE_CURRENT_BINARY_DIR}/generated/globals.h)
set(GLOBALS_C ${CMAKE_CURRENT_BINARY_DIR}/generated/globals.c)
set(GLOBALS_H_COG ${PROJECT_SOURCE_DIR}/src/globals.h.cog)
set(GLOBALS_C_COG ${PROJECT_SOURCE_DIR}/src/globals.c.cog)

make_directory(${CMAKE_CURRENT_BINARY_DIR}/generated)
include_directories(${CMAKE_CURRENT_BINARY_DIR}/generated)

if(NOT PLAT_MSVC)
    set(PYTHON_EXE "${CMAKE_CURRENT_BINARY_DIR}/cogapp_venv/bin/python3")
    set(COGAPP_DEPENDS "${CMAKE_CURRENT_BINARY_DIR}/cogapp_venv/bin/cog")
else()
    find_package(Python3 COMPONENTS Interpreter REQUIRED)

    # Print the Python executable path
    message(STATUS "Python executable: ${Python3_EXECUTABLE}")

    # Added: provision cog ourselves instead of requiring a manual
    # `pip3 install cogapp` before the first configure. If the interpreter CMake
    # found already provides cogapp we use it as-is (so an offline machine that
    # installed it by hand keeps working); otherwise a venv is created beside the
    # build tree and cogapp installed into it. The non-MSVC branch above does the
    # same thing at build time, but its POSIX venv layout (bin/python3) and its
    # bare `python3` launcher do not exist on Windows, so this is done here at
    # configure time, where Visual Studio surfaces the errors legibly.
    execute_process(
        COMMAND ${Python3_EXECUTABLE} -c "import cogapp"
        RESULT_VARIABLE COGAPP_IMPORT_RESULT
        OUTPUT_QUIET
        ERROR_QUIET
    )

    if(COGAPP_IMPORT_RESULT EQUAL 0)
        message(STATUS "Using cogapp from ${Python3_EXECUTABLE}")
        set(PYTHON_EXE "${Python3_EXECUTABLE}")
    else()
        set(COGAPP_VENV "${CMAKE_CURRENT_BINARY_DIR}/cogapp_venv")
        set(PYTHON_EXE "${COGAPP_VENV}/Scripts/python.exe")

        if(NOT EXISTS "${PYTHON_EXE}")
            message(STATUS "cogapp not available, creating venv in ${COGAPP_VENV}")
            execute_process(
                COMMAND ${Python3_EXECUTABLE} -m venv "${COGAPP_VENV}"
                RESULT_VARIABLE COGAPP_VENV_RESULT
            )
            if(NOT COGAPP_VENV_RESULT EQUAL 0)
                message(FATAL_ERROR
                    "Failed to create a venv for cog using ${Python3_EXECUTABLE}. "
                    "Install cog yourself (`pip install cogapp`) and reconfigure.")
            endif()
        endif()

        execute_process(
            COMMAND ${PYTHON_EXE} -c "import cogapp"
            RESULT_VARIABLE COGAPP_VENV_IMPORT_RESULT
            OUTPUT_QUIET
            ERROR_QUIET
        )
        if(NOT COGAPP_VENV_IMPORT_RESULT EQUAL 0)
            message(STATUS "Installing cogapp into ${COGAPP_VENV}")
            execute_process(
                COMMAND ${PYTHON_EXE} -m pip install cogapp
                RESULT_VARIABLE COGAPP_PIP_RESULT
            )
            if(NOT COGAPP_PIP_RESULT EQUAL 0)
                message(FATAL_ERROR
                    "Failed to install cogapp into ${COGAPP_VENV} (no network?). "
                    "Install cog yourself (`pip install cogapp`) and reconfigure.")
            endif()
        endif()
    endif()

    set(COGAPP_DEPENDS "${PYTHON_EXE}")
endif()

list(JOIN EMBEDDED_RESOURCES "+" EMBEDDED_RESOURCES_SEPARATED)

# All of our pre-build steps
add_custom_command(
    OUTPUT ${GLOBALS_C}
    COMMAND ${PYTHON_EXE} -m cogapp -d -D symbols_fpath="${SYMBOLS_FILE}" -D project_root="${PROJECT_SOURCE_DIR}" -D embedded_resources="${EMBEDDED_RESOURCES_SEPARATED}" -o ${GLOBALS_C} ${GLOBALS_C_COG}
    DEPENDS ${SYMBOLS_FILE} ${GLOBALS_C_COG} ${GLOBALS_H} ${EMBEDDED_RESOURCES} ${PYTHON_EXE} ${COGAPP_DEPENDS}
)

if(NOT PLAT_MSVC)
    add_custom_command(
        OUTPUT ${PYTHON_EXE}
        COMMAND python3 -m venv ${CMAKE_CURRENT_BINARY_DIR}/cogapp_venv
    )
    add_custom_command(
        OUTPUT ${COGAPP_DEPENDS}
        COMMAND ${PYTHON_EXE} -m pip install cogapp
        DEPENDS ${PYTHON_EXE}
    )
endif()

add_custom_command(
    OUTPUT ${GLOBALS_H}
    COMMAND ${PYTHON_EXE} -m cogapp -d -D symbols_fpath="${SYMBOLS_FILE}" -D project_root="${PROJECT_SOURCE_DIR}" -D embedded_resources="${EMBEDDED_RESOURCES_SEPARATED}" -o ${GLOBALS_H} ${GLOBALS_H_COG}
    DEPENDS ${SYMBOLS_FILE} ${GLOBALS_H_COG} ${PYTHON_EXE} ${COGAPP_DEPENDS} ${EMBEDDED_RESOURCES}
)

# Gather the cog generation into one target. Many sith_engine translation units
# include generated/globals.h transitively (via rdMaterial.h etc.), but CMake has
# no way to know that on a clean build, so a high -j build would compile them while
# cog is still writing globals.h and read a truncated header ("unterminated
# #ifndef"). add_dependencies(sith_engine generate_globals) (in CMakeLists.txt)
# makes every sith_engine object wait for this target to finish first.
set_source_files_properties(${GLOBALS_H} ${GLOBALS_C} PROPERTIES GENERATED TRUE)
add_custom_target(generate_globals DEPENDS ${GLOBALS_H} ${GLOBALS_C})

# HACK
list(REMOVE_ITEM ENGINE_SOURCE_FILES ${GLOBALS_C})
list(APPEND ENGINE_SOURCE_FILES ${GLOBALS_C})