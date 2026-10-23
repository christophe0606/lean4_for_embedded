cmake_minimum_required(VERSION 3.24)
project(LeanEmbedded LANGUAGES C CXX ASM)
if(NOT CMAKE_BUILD_TYPE)
  set(CMAKE_BUILD_TYPE Debug CACHE STRING "Build configuration" FORCE)
endif()
set(CMAKE_CXX_STANDARD 20)
set(CMAKE_C_STANDARD 11)
set(CMAKE_EXPORT_COMPILE_COMMANDS ON)
find_package(Python3 REQUIRED COMPONENTS Interpreter)
find_program(LEAN_EXECUTABLE lean REQUIRED HINTS "$ENV{ELAN_HOME}/bin")
set(LEAN_SOURCE_DIR "${CMAKE_SOURCE_DIR}/.reference/lean4" CACHE PATH "Pinned upstream Lean sources")
set(CMSIS_PACK_ROOT "$ENV{CMSIS_PACK_ROOT}" CACHE PATH "Installed CMSIS packs")
if(NOT EXISTS "${LEAN_SOURCE_DIR}/src/runtime/object.cpp")
  message(FATAL_ERROR "Fetch upstream sources first: scripts/fetch-sources.py")
endif()
execute_process(COMMAND "${LEAN_EXECUTABLE}" --version WORKING_DIRECTORY "${CMAKE_SOURCE_DIR}" OUTPUT_VARIABLE LEAN_VERSION COMMAND_ERROR_IS_FATAL ANY)
if(NOT LEAN_VERSION MATCHES "version 4.35.0,")
  message(FATAL_ERROR "Expected stock Lean 4.35.0, got ${LEAN_VERSION}")
endif()
set_property(DIRECTORY APPEND PROPERTY CMAKE_CONFIGURE_DEPENDS "${CMAKE_SOURCE_DIR}/scripts/prepare-runtime.py" "${CMAKE_SOURCE_DIR}/upstream.json")
execute_process(COMMAND "${LEAN_EXECUTABLE}" --githash WORKING_DIRECTORY "${CMAKE_SOURCE_DIR}"
  OUTPUT_VARIABLE LEAN_HOST_COMMIT OUTPUT_STRIP_TRAILING_WHITESPACE COMMAND_ERROR_IS_FATAL ANY)
file(READ "${CMAKE_SOURCE_DIR}/upstream.json" LEAN_PIN)
string(JSON LEAN_PIN_COMMIT GET "${LEAN_PIN}" commit)
if(NOT LEAN_HOST_COMMIT STREQUAL LEAN_PIN_COMMIT)
  message(FATAL_ERROR "Host Lean compiler and runtime sources must have the same commit")
endif()
set(UPSTREAM "${CMAKE_BINARY_DIR}/upstream")
execute_process(COMMAND "${Python3_EXECUTABLE}" "${CMAKE_SOURCE_DIR}/scripts/prepare-runtime.py" "${LEAN_SOURCE_DIR}" "${UPSTREAM}"
  RESULT_VARIABLE PREPARE_RUNTIME_STATUS ERROR_VARIABLE PREPARE_RUNTIME_ERROR)
if(NOT PREPARE_RUNTIME_STATUS EQUAL 0)
  string(REPLACE "\n" " | " PREPARE_RUNTIME_MESSAGE "${PREPARE_RUNTIME_ERROR}")
  message(FATAL_ERROR "prepare-runtime.py failed: ${PREPARE_RUNTIME_MESSAGE}")
endif()
file(WRITE "${UPSTREAM}/githash.h" "#define LEAN_GITHASH \"eb6cafb7290e8bd5f2937522d8d804f58f02bafc\"\n")
execute_process(COMMAND "${LEAN_EXECUTABLE}" --print-prefix WORKING_DIRECTORY "${CMAKE_SOURCE_DIR}" OUTPUT_VARIABLE LEAN_PREFIX OUTPUT_STRIP_TRAILING_WHITESPACE COMMAND_ERROR_IS_FATAL ANY)
configure_file("${LEAN_PREFIX}/include/lean/version.h" "${UPSTREAM}/include/lean/version.h" COPYONLY)
set(LEAN_BOARD "Corstone300" CACHE STRING "Firmware board")
if(LEAN_BOARD STREQUAL "DevKit-E8")
  set(BSP "${CMSIS_PACK_ROOT}/AlifSemiconductor/Ensemble/2.2.1")
  set(BOARD_DIR "${CMAKE_SOURCE_DIR}/board/DevKit-E8")
  set(BOARD_RTE "${BOARD_DIR}/RTE/Device/AE822FA0E5597LS0_M55_HP")
  if(NOT IS_ABSOLUTE "${LEAN_BOARD_LAYER}")
    set(LEAN_BOARD_LAYER "${CMAKE_SOURCE_DIR}/${LEAN_BOARD_LAYER}")
  endif()
  if(NOT EXISTS "${BSP}/AlifSemiconductor.Ensemble.pdsc")
    message(FATAL_ERROR "AlifSemiconductor::Ensemble@2.2.1 is required")
  endif()
  if(NOT EXISTS "${LEAN_BOARD_LAYER}")
    message(FATAL_ERROR "DevKit-E8 requires an existing -DLEAN_BOARD_LAYER path")
  endif()
  set_property(DIRECTORY APPEND PROPERTY CMAKE_CONFIGURE_DEPENDS "${LEAN_BOARD_LAYER}")
  set(BOARD_INCLUDES
    "${BOARD_DIR}"
    "${BSP}/Boards/DevKit-e8"
    "${BSP}/Device/core/common/include"
    "${BSP}/Device/system/include"
    "${BSP}/Device/soc/AE822FA0E5597/include"
    "${BSP}/Device/soc/AE822FA0E5597/include/rtss_hp"
    "${BSP}/drivers/include"
    "${BSP}/Alif_CMSIS/Include"
    "${BSP}/Alif_CMSIS/Source"
    "${CMSIS_PACK_ROOT}/ARM/CMSIS/6.3.0/CMSIS/Driver/Include"
    "${BOARD_RTE}")
  set(BOARD_SOURCES
    "${BOARD_DIR}/start.c" "${BOARD_DIR}/stdio.c"
    "${BSP}/Device/core/common/source/startup.c"
    "${BSP}/Device/core/common/source/system.c"
    "${BSP}/Device/core/common/source/vectors.c"
    "${BSP}/Device/core/common/source/tgu.c"
    "${BSP}/Device/core/common/source/sau_tcm_ns_setup.c"
    "${BSP}/Device/core/common/source/mpu.c"
    "${BSP}/Device/core/common/source/cache.c"
    "${BSP}/Device/core/common/source/pm.c"
    "${BSP}/Device/system/source/sys_clocks.c"
    "${BSP}/Device/system/source/sys_utils.c"
    "${BSP}/Alif_CMSIS/Source/Driver_USART.c"
    "${BSP}/drivers/source/uart.c"
    "${BSP}/drivers/source/pinconf.c")
  set(BOARD_DEFINES LEAN_BOARD_ALIF_E8 RTSS_HP ENSEMBLE_SOC_GEN2 AE822FA0E5597LS0 RTE_Drivers_USART CMSIS_device_header="alif.h")
  set(BOARD_DEVICE_HEADER "alif.h")
elseif(LEAN_BOARD STREQUAL "Corstone300")
  set(BSP "${CMSIS_PACK_ROOT}/ARM/V2M_MPS3_SSE_300_BSP/1.4.0")
  set(BOARD_INCLUDES "${BSP}/Device/Include" "${BSP}/Board/Platform")
  set(BOARD_SOURCES board/Corstone300/start.c board/Corstone300/fault.c
    "${BSP}/Device/Source/startup_SSE300MPS3.c" "${BSP}/Device/Source/system_SSE300MPS3.c")
  set(BOARD_DEVICE_HEADER "SSE300MPS3.h")
else()
  message(FATAL_ERROR "Unsupported LEAN_BOARD=${LEAN_BOARD}")
endif()
set(CORE "${CMSIS_PACK_ROOT}/ARM/CMSIS/6.3.0/CMSIS/Core/Include")
set(RTX "${CMSIS_PACK_ROOT}/ARM/CMSIS-RTX/5.9.1")
set(RTOS_API "${CMSIS_PACK_ROOT}/ARM/CMSIS/6.3.0/CMSIS/RTOS2/Include")
set(RUNTIME_SOURCES mpz utf8 object apply hash mpn byteslice alloc thread exception interrupt debug mutex platform object_ref stackinfo cmsis_portable_io cmsis_console_io)
foreach(name IN LISTS RUNTIME_SOURCES)
  list(APPEND RUNTIME_FILES "${UPSTREAM}/runtime/${name}.cpp")
endforeach()
add_library(leanrt STATIC ${RUNTIME_FILES} runtime/platform.cpp runtime/cmsis_thread.cpp runtime/cmsis_tls.cpp runtime/cmsis_tp.S runtime/cmsis_libc.cpp runtime/cmsis_console.cpp)
target_include_directories(leanrt PUBLIC runtime/include "${UPSTREAM}/include" PRIVATE "${UPSTREAM}" PUBLIC runtime "${RTOS_API}" ${BOARD_INCLUDES} "${CORE}")
target_compile_definitions(leanrt PUBLIC LEAN_CMSIS LEAN_MULTI_THREAD ${BOARD_DEFINES} PRIVATE LEAN_DEFAULT_THREAD_STACK_SIZE=16384 LEAN_STACK_BUFFER_SPACE=1024 LEAN_BUILD_TYPE=Release)
target_link_options(leanrt INTERFACE -Wl,-u,__retarget_lock_acquire,-u,__cxa_guard_acquire)
target_compile_options(leanrt PRIVATE -Os -Wno-unused-parameter)
set(GEN "${CMAKE_BINARY_DIR}/generated")
file(MAKE_DIRECTORY "${GEN}")
find_program(LAKE_EXECUTABLE lake REQUIRED HINTS "$ENV{ELAN_HOME}/bin")
file(GLOB_RECURSE LEAN_PACKAGE_INPUTS CONFIGURE_DEPENDS
  "${CMAKE_SOURCE_DIR}/examples/*.lean" "${CMAKE_SOURCE_DIR}/examples/*lakefile.toml"
  "${CMAKE_SOURCE_DIR}/lean/*.lean")
set_property(DIRECTORY APPEND PROPERTY CMAKE_CONFIGURE_DEPENDS
  "${CMAKE_SOURCE_DIR}/lakefile.toml" "${CMAKE_SOURCE_DIR}/scripts/lean-sources.py" ${LEAN_PACKAGE_INPUTS})
set(LEAN_APP "Smoke" CACHE STRING "Firmware application")
if(LEAN_APP STREQUAL "Blinky")
  if(NOT LEAN_BOARD STREQUAL "DevKit-E8")
    message(FATAL_ERROR "Lean Blinky requires DevKit-E8")
  endif()
  set(LEAN_GENERATE_MODULES --module Blinky)
else()
  set(LEAN_GENERATE_MODULES --module Smoke)
  if(LEAN_PROFILE STREQUAL "Console")
    list(APPEND LEAN_GENERATE_MODULES --module Console)
  endif()
endif()
execute_process(COMMAND "${Python3_EXECUTABLE}" "${CMAKE_SOURCE_DIR}/scripts/lean-sources.py"
  --root "${CMAKE_SOURCE_DIR}" --upstream "${LEAN_SOURCE_DIR}" --output "${GEN}"
  --lake "${LAKE_EXECUTABLE}" ${LEAN_GENERATE_MODULES}
  OUTPUT_VARIABLE LEAN_GEN_OUT ERROR_VARIABLE LEAN_GEN_ERR RESULT_VARIABLE LEAN_GEN_STATUS)
if(NOT LEAN_GEN_STATUS EQUAL 0)
  string(REPLACE "\n" " | " LEAN_GEN_MESSAGE "${LEAN_GEN_OUT} ${LEAN_GEN_ERR}")
  message("${CMAKE_SOURCE_DIR}/scripts/lean-sources.py:1:1: error: ${LEAN_GEN_MESSAGE}")
  message(FATAL_ERROR "${LEAN_GEN_MESSAGE}")
endif()
include("${GEN}/sources.cmake")
set_property(DIRECTORY APPEND PROPERTY CMAKE_CONFIGURE_DEPENDS ${LEAN_INPUT_FILES})
message(STATUS "Lean firmware module closure: ${LEAN_MODULE_COUNT} modules")
add_library(lean_app STATIC ${LEAN_C_FILES})
target_link_libraries(lean_app PUBLIC leanrt)
target_compile_options(lean_app PRIVATE -Os)
file(GLOB RTX_C CONFIGURE_DEPENDS "${RTX}/Source/rtx_*.c")
add_library(rtx STATIC ${RTX_C} "${RTX}/Source/GCC/irq_armv8mml.S"
  "${RTX}/Config/RTX_Config.c" "${CMSIS_PACK_ROOT}/ARM/CMSIS/6.3.0/CMSIS/RTOS2/Source/os_systick.c")
target_include_directories(rtx PUBLIC "${RTX}/Include" "${RTX}/Config" "${RTOS_API}" "${CORE}" ${BOARD_INCLUDES})
target_compile_definitions(rtx PRIVATE RTE_COMPONENTS_H CMSIS_device_header="${BOARD_DEVICE_HEADER}" ${BOARD_DEFINES} OS_DYNAMIC_MEM_SIZE=131072 OS_STACK_SIZE=16384 OS_TIMER_THREAD_STACK_SIZE=2048 OS_STACK_CHECK=1)
target_compile_options(rtx PRIVATE -Os)
if(LEAN_APP STREQUAL "Blinky")
  set(FIRMWARE_TARGET lean-blinky.elf)
  set(FIRMWARE_MAP lean-blinky.map)
  list(APPEND BOARD_SOURCES "${BSP}/Alif_CMSIS/Source/Driver_GPIO.c")
  add_executable(${FIRMWARE_TARGET} examples/blinky/main.c examples/blinky/hardware_bridge.c ${BOARD_SOURCES})
  target_compile_definitions(${FIRMWARE_TARGET} PRIVATE RTE_Drivers_GPIO)
elseif(LEAN_APP STREQUAL "Smoke")
  set(FIRMWARE_TARGET lean-smoke.elf)
  set(FIRMWARE_MAP lean-smoke.map)
  add_executable(${FIRMWARE_TARGET} examples/smoke/main.c examples/smoke/systick.c examples/smoke/timer_sequence.c runtime/selftest.cpp ${BOARD_SOURCES})
else()
  message(FATAL_ERROR "Unsupported LEAN_APP=${LEAN_APP}")
endif()
target_include_directories(${FIRMWARE_TARGET} PRIVATE "${UPSTREAM}" "${GEN}" ${BOARD_INCLUDES} "${CORE}")
target_compile_definitions(${FIRMWARE_TARGET} PRIVATE __PROGRAM_START=embedded_start ${BOARD_DEFINES})
if(LEAN_APP STREQUAL "Smoke" AND LEAN_PROFILE STREQUAL "Console")
  target_compile_definitions(${FIRMWARE_TARGET} PRIVATE LEAN_CONSOLE_EXAMPLE)
endif()
if(CMAKE_C_COMPILER_ID STREQUAL "GNU")
  target_compile_options(leanrt PUBLIC -fpermitted-flt-eval-methods=c11)
endif()
target_link_libraries(${FIRMWARE_TARGET} PRIVATE lean_app leanrt rtx)
if(LEAN_BOARD STREQUAL "DevKit-E8")
  target_link_options(${FIRMWARE_TARGET} PRIVATE --specs=nosys.specs)
elseif(CMAKE_C_COMPILER_ID STREQUAL "GNU")
  target_link_options(${FIRMWARE_TARGET} PRIVATE --specs=rdimon.specs)
else()
  target_link_libraries(${FIRMWARE_TARGET} PRIVATE semihost)
endif()
if(LEAN_BOARD STREQUAL "DevKit-E8")
  set(LEAN_LINKER_SCRIPT "${BOARD_DIR}/memory.ld")
elseif(LEAN_PROFILE STREQUAL "Console")
  set(LEAN_LINKER_SCRIPT "${CMAKE_SOURCE_DIR}/board/Corstone300/memory-console.ld")
else()
  set(LEAN_LINKER_SCRIPT "${CMAKE_SOURCE_DIR}/board/Corstone300/memory.ld")
endif()
target_link_options(${FIRMWARE_TARGET} PRIVATE -nostartfiles
  "-T${LEAN_LINKER_SCRIPT}" -Wl,--gc-sections
  "-Wl,-Map=${CMAKE_BINARY_DIR}/${FIRMWARE_MAP}")
set_property(TARGET ${FIRMWARE_TARGET} APPEND PROPERTY LINK_DEPENDS "${LEAN_LINKER_SCRIPT}")
