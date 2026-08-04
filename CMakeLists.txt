cmake_minimum_required(VERSION 3.18)

project(FlexCTM VERSION 0.1.0 LANGUAGES Fortran)

if (NOT CMAKE_BUILD_TYPE AND NOT CMAKE_CONFIGURATION_TYPES)
  set(CMAKE_BUILD_TYPE Release CACHE STRING "Build type" FORCE)
  set_property(CACHE CMAKE_BUILD_TYPE PROPERTY STRINGS Debug Release)
endif ()

include(FetchContent)
include(CTest)

option(FLEXCTM_REAL32 "Build FlexCTM and numerical dependencies with real32" OFF)
set(
  FLEXCTM_DEPENDENCY_DIR "${CMAKE_CURRENT_SOURCE_DIR}/build/dependencies"
  CACHE PATH "Shared source directory for downloaded dependencies"
)

set(CMAKE_RUNTIME_OUTPUT_DIRECTORY "${CMAKE_CURRENT_BINARY_DIR}/bin")
set(CMAKE_LIBRARY_OUTPUT_DIRECTORY "${CMAKE_CURRENT_BINARY_DIR}/lib")
set(CMAKE_ARCHIVE_OUTPUT_DIRECTORY "${CMAKE_CURRENT_BINARY_DIR}/lib")
set(FLEXCTM_MODULE_DIR "${CMAKE_CURRENT_BINARY_DIR}/modules")

find_package(MPI REQUIRED COMPONENTS Fortran)

# NetCDF Fortran flags are obtained from the installation's nf-config.
find_program(NF_CONFIG nf-config REQUIRED)
execute_process(
  COMMAND ${NF_CONFIG} --fflags
  OUTPUT_VARIABLE NETCDF_FORTRAN_FLAGS
  OUTPUT_STRIP_TRAILING_WHITESPACE
)
execute_process(
  COMMAND ${NF_CONFIG} --flibs
  OUTPUT_VARIABLE NETCDF_FORTRAN_LIBS
  OUTPUT_STRIP_TRAILING_WHITESPACE
)
separate_arguments(NETCDF_FORTRAN_FLAGS NATIVE_COMMAND "${NETCDF_FORTRAN_FLAGS}")
separate_arguments(NETCDF_FORTRAN_LIBS NATIVE_COMMAND "${NETCDF_FORTRAN_LIBS}")

set(FLEXCTM_DEPENDENCIES
  parallel
  container
  projection
  datetime
  ysu
  advection
  diffusion
)

# Keep the ABI of all numerical packages consistent with the model precision.
set(ADVECTION_REAL32  ${FLEXCTM_REAL32} CACHE BOOL "" FORCE)
set(DIFFUSION_REAL32  ${FLEXCTM_REAL32} CACHE BOOL "" FORCE)
set(PROJECTION_REAL32 ${FLEXCTM_REAL32} CACHE BOOL "" FORCE)
set(YSU_REAL32        ${FLEXCTM_REAL32} CACHE BOOL "" FORCE)

# Reuse complete checkouts in build/dependencies. FetchContent downloads only
# missing packages; each CMake binary directory keeps its own build products.
foreach(dependency IN LISTS FLEXCTM_DEPENDENCIES)
  set(dependency_source "${FLEXCTM_DEPENDENCY_DIR}/${dependency}")
  if (EXISTS "${dependency_source}/CMakeLists.txt")
    add_subdirectory(
      "${dependency_source}"
      "${CMAKE_CURRENT_BINARY_DIR}/dependencies/${dependency}"
    )
  elseif (EXISTS "${dependency_source}")
    message(FATAL_ERROR "Incomplete dependency checkout: ${dependency_source}")
  else ()
    FetchContent_Declare(
      ${dependency}
      GIT_REPOSITORY "https://github.com/FlexCTM/${dependency}.git"
      GIT_SHALLOW TRUE
      SOURCE_DIR "${dependency_source}"
      BINARY_DIR "${CMAKE_CURRENT_BINARY_DIR}/dependencies/${dependency}"
    )
    FetchContent_MakeAvailable(${dependency})
  endif ()
endforeach()

set(FLEXCTM_SOURCES
  src/module_constant.F90
  src/module_error.F90
  src/module_namelist.F90
  src/module_tool.F90
  src/module_chem_type.F90
  src/module_chem_csv.F90
  src/module_mete_type.F90
  src/module_mete_csv.F90
  src/module_mesh_type.F90
  src/module_block_type.F90
  src/module_ncio.F90
  src/module_output.F90
  src/module_initial.F90
  src/module_boundary.F90
  src/module_emission.F90
  src/module_meteorology_mock.F90
  src/module_meteorology_wrf.F90
  src/module_meteorology.F90
  src/module_mete_diagnostic.F90
  src/drive/module_drive_adv.F90
  src/drive/module_drive_diff.F90
)

function(flexctm_set_fortran_options target)
  if (CMAKE_Fortran_COMPILER_ID STREQUAL "GNU")
    target_compile_options(${target} PRIVATE -ffree-line-length-none)
    target_compile_options(${target} PRIVATE "$<$<CONFIG:Debug>:-g;-fbacktrace;-fcheck=all>")
  elseif (CMAKE_Fortran_COMPILER_ID MATCHES "Intel|IntelLLVM")
    target_compile_options(${target} PRIVATE -no-wrap-margin)
    target_compile_options(${target} PRIVATE "$<$<CONFIG:Debug>:-g;-traceback;-check;bounds>")
  endif ()
endfunction()

add_library(FlexCTM ${FLEXCTM_SOURCES})
set_target_properties(FlexCTM PROPERTIES
  Fortran_MODULE_DIRECTORY "${FLEXCTM_MODULE_DIR}"
)
target_include_directories(FlexCTM PUBLIC
  "$<BUILD_INTERFACE:${FLEXCTM_MODULE_DIR}>"
)
if (FLEXCTM_REAL32)
  target_compile_definitions(FlexCTM PUBLIC FLEXCTM_REAL32)
endif ()
flexctm_set_fortran_options(FlexCTM)
target_compile_options(FlexCTM PUBLIC ${NETCDF_FORTRAN_FLAGS})
target_link_libraries(FlexCTM PUBLIC
  MPI::MPI_Fortran
  parallel
  container
  projection
  datetime
  ysu
  advection
  diffusion
  ${NETCDF_FORTRAN_LIBS}
)

add_executable(FlexCTM.exe app/main.f90)
flexctm_set_fortran_options(FlexCTM.exe)
target_link_libraries(FlexCTM.exe PRIVATE FlexCTM)

if (BUILD_TESTING)
  set(TESTDRIVE_BUILD_TESTING OFF CACHE BOOL "" FORCE)
  set(test_drive_source "${FLEXCTM_DEPENDENCY_DIR}/test-drive")
  if (EXISTS "${test_drive_source}/CMakeLists.txt")
    add_subdirectory(
      "${test_drive_source}"
      "${CMAKE_CURRENT_BINARY_DIR}/dependencies/test-drive"
    )
  elseif (EXISTS "${test_drive_source}")
    message(FATAL_ERROR "Incomplete dependency checkout: ${test_drive_source}")
  else ()
    FetchContent_Declare(
      test_drive
      GIT_REPOSITORY "https://github.com/fortran-lang/test-drive.git"
      GIT_TAG v0.6.0
      GIT_SHALLOW TRUE
      SOURCE_DIR "${test_drive_source}"
      BINARY_DIR "${CMAKE_CURRENT_BINARY_DIR}/dependencies/test-drive"
    )
    FetchContent_MakeAvailable(test_drive)
  endif ()

  file(GLOB FLEXCTM_TEST_SOURCES CONFIGURE_DEPENDS "${CMAKE_CURRENT_SOURCE_DIR}/test/*.f90")
  foreach(test_source IN LISTS FLEXCTM_TEST_SOURCES)
    get_filename_component(test_name "${test_source}" NAME_WE)
    set(test_target "flexctm_test_${test_name}")
    add_executable(${test_target} "${test_source}")
    set_target_properties(${test_target} PROPERTIES
      Fortran_MODULE_DIRECTORY "${CMAKE_CURRENT_BINARY_DIR}/test-modules/${test_name}"
      RUNTIME_OUTPUT_DIRECTORY "${CMAKE_CURRENT_BINARY_DIR}/test"
    )
    flexctm_set_fortran_options(${test_target})
    target_link_libraries(${test_target} PRIVATE FlexCTM test-drive)
    add_test(NAME ${test_name} COMMAND ${test_target})
    set_tests_properties(${test_name} PROPERTIES
      WORKING_DIRECTORY "${CMAKE_CURRENT_SOURCE_DIR}"
      TIMEOUT 60
    )
  endforeach()
endif ()
