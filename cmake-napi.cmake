include_guard()

set(napi_module_dir "${CMAKE_CURRENT_LIST_DIR}")

function(download_node_headers result)
  cmake_parse_arguments(
    PARSE_ARGV 1 ARGV "" "DESTINATION;IMPORT_FILE;VERSION" ""
  )

  if(NOT ARGV_DESTINATION)
    set(ARGV_DESTINATION "${CMAKE_CURRENT_BINARY_DIR}")
  endif()

  if(NOT ARGV_VERSION)
    set(ARGV_VERSION "20.17.0")
  endif()

  set(version "v${ARGV_VERSION}")

  set(archive "${CMAKE_CURRENT_BINARY_DIR}/node-${version}.tar.gz")

  file(DOWNLOAD
    "https://nodejs.org/download/release/${version}/node-${version}-headers.tar.gz"
    "${archive}"
  )

  file(ARCHIVE_EXTRACT
    INPUT "${archive}"
    DESTINATION "${ARGV_DESTINATION}"
  )

  set(import_file ${ARGV_IMPORT_FILE})

  if(import_file)
    if(MSVC)
      set(arch "${CMAKE_GENERATOR_PLATFORM}")

      string(TOLOWER "${arch}" arch)

      set(lib "${ARGV_DESTINATION}/node-${version}/lib/node.lib")

      file(DOWNLOAD
        "https://nodejs.org/download/release/${version}/win-${arch}/node.lib"
        "${lib}"
      )

      set(${import_file} "${lib}")
    else()
      set(${import_file} ${import_file}-NOTFOUND)
    endif()
  endif()

  set(${result} "${ARGV_DESTINATION}/node-${version}/include/node")

  return(PROPAGATE ${result} ${import_file})
endfunction()

function(napi_module_target directory result)
  cmake_parse_arguments(
    PARSE_ARGV 2 ARGV "" "NAME;VERSION;HASH" ""
  )

  set(package_path package.json)

  cmake_path(ABSOLUTE_PATH directory NORMALIZE)

  cmake_path(ABSOLUTE_PATH package_path BASE_DIRECTORY "${directory}" NORMALIZE)

  file(READ "${package_path}" package)

  string(JSON name GET "${package}" "name")

  string(REGEX REPLACE "/" "+" name ${name})

  string(JSON version GET "${package}" "version")

  string(SHA256 hash "napi ${package_path}")

  string(SUBSTRING "${hash}" 0 8 hash)

  set(${result} "${name}-${version}-${hash}")

  if(ARGV_NAME)
    set(${ARGV_NAME} ${name})
  endif()

  if(ARGV_VERSION)
    set(${ARGV_VERSION} ${version})
  endif()

  if(ARGV_HASH)
    set(${ARGV_HASH} ${hash})
  endif()

  return(PROPAGATE ${result} ${ARGV_NAME} ${ARGV_VERSION} ${ARGV_HASH})
endfunction()

function(add_napi_module result)
  napi_module_target("." target NAME name)

  download_node_headers(node_headers IMPORT_FILE node_lib)

  add_library(${target} OBJECT)

  set_target_properties(
    ${target}
    PROPERTIES
    C_STANDARD 11
    CXX_STANDARD 20
    POSITION_INDEPENDENT_CODE ON
  )

  target_include_directories(
    ${target}
    PRIVATE
      ${node_headers}
  )

  set(${result} ${target})

  if(IOS OR ANDROID)
    return(PROPAGATE ${result})
  endif()

  add_executable(${target}_import_lib IMPORTED)

  set_target_properties(
    ${target}_import_lib
    PROPERTIES
    ENABLE_EXPORTS ON
    IMPORTED_IMPLIB "${node_lib}"
  )

  add_library(${target}_module SHARED)

  set_target_properties(
    ${target}_module
    PROPERTIES
    OUTPUT_NAME ${name}
    PREFIX ""
    SUFFIX ".node"

    # Don't set a shared library name to allow loading the resulting library as
    # a plugin.
    NO_SONAME ON

    # Automatically export all available symbols on Windows. Without this,
    # module authors would have to explicitly export public symbols.
    WINDOWS_EXPORT_ALL_SYMBOLS ON
  )

  if(MSVC)
    target_link_options(
      ${target}_module
      PRIVATE
        /DELAYLOAD:node.exe
        /NOIMPLIB
    )

    target_sources(
      ${target}_module
      PRIVATE
        "${napi_module_dir}/win32/delay-load.c"
    )
  else()
    target_link_options(
      ${target}_module
      PRIVATE
        -Wl,-undefined,dynamic_lookup
    )
  endif()

  target_link_libraries(
    ${target}_module
    PUBLIC
      ${target}
    PRIVATE
      ${target}_import_lib
  )

  return(PROPAGATE ${result})
endfunction()
