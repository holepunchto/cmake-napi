cmake_minimum_required(VERSION 3.25)

find_package(cmake-napi REQUIRED PATHS node_modules/cmake-napi)

project(napi_runtime_dependency C)

add_library(bar SHARED)

target_sources(
  bar
  PRIVATE
    bar.c
)

add_library(foo SHARED)

target_sources(
  foo
  PRIVATE
    foo.c
)

target_link_libraries(
  foo
  PRIVATE
    bar
)

# The addon carries a runpath to the directory its dependencies are installed
# into, but that only covers the dependencies it names itself. Everything in
# that directory that depends on a sibling needs a runpath of its own.
if(APPLE)
  set(rpath "@loader_path")
elseif(LINUX)
  set(rpath "$ORIGIN")
else()
  set(rpath "")
endif()

set_target_properties(
  bar
  foo

  PROPERTIES

  WINDOWS_EXPORT_ALL_SYMBOLS ON
  INSTALL_RPATH "${rpath}"
  BUILD_WITH_INSTALL_RPATH ON
)

add_napi_module(addon INSTALL TARGET foo TARGET bar)

target_sources(
  ${addon}
  PRIVATE
    binding.c
)

target_link_libraries(
  ${addon}
  PRIVATE
    foo
)

# PE has no runpath, so the addon's dependencies are found by the delay load
# hook rather than by the loader.
if(WIN32)
  target_link_options(
    ${addon}_module
    PRIVATE
      /DELAYLOAD:foo.dll
  )
endif()
