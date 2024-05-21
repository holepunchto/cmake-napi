set(napi_module_dir "${CMAKE_CURRENT_LIST_DIR}")

function(find_node result)
  if(WIN32)
    find_program(
      node_bin
      NAMES node.cmd node
      REQUIRED
    )
  else()
    find_program(
      node_bin
      NAMES node
      REQUIRED
    )
  endif()

  execute_process(
    COMMAND "${node_bin}" -p "process.argv[0]"
    OUTPUT_VARIABLE node
    OUTPUT_STRIP_TRAILING_WHITESPACE
    COMMAND_ERROR_IS_FATAL ANY
  )

  set(${result} "${node}")

  return(PROPAGATE ${result})
endfunction()

function(download_node_headers result)
  cmake_parse_arguments(
    PARSE_ARGV 1 ARGV "" "DESTINATION;VERSION" ""
  )

  if(NOT ARGV_DESTINATION)
    set(ARGV_DESTINATION "${CMAKE_CURRENT_BINARY_DIR}")
  endif()

  if(NOT ARGV_VERSION)
    set(ARGV_VERSION "20.13.1")
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

  if(MSVC)
    # TODO: Download .lib for Windows
  endif()

  set(${result} "${ARGV_DESTINATION}/node-${version}")

  return(PROPAGATE ${result})
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

  download_node_headers(headers)

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
      "${headers}/include/node"
  )

  find_node(node)

  add_executable(${target}_import_lib IMPORTED)

  set_target_properties(
    ${target}_import_lib
    PROPERTIES
    ENABLE_EXPORTS ON
    IMPORTED_LOCATION "${node}"
  )

  if(MSVC)
    find_library(
      node_lib
      NAMES node
      HINTS "${headers}/lib"
    )

    set_target_properties(
      ${target}_import_lib
      PROPERTIES
      IMPORTED_IMPLIB "${node_lib}"
    )

    target_link_options(
      ${target}_import_lib
      INTERFACE
        /DELAYLOAD:node.exe
    )
  endif()

  add_library(${target}_module MODULE)

  set_target_properties(
    ${target}_module
    PROPERTIES
    OUTPUT_NAME ${name}
    PREFIX ""
    SUFFIX ".node"

    # Automatically export all available symbols on Windows. Without this,
    # module authors would have to explicitly export public symbols.
    WINDOWS_EXPORT_ALL_SYMBOLS ON
  )

  if(MSVC)
    target_sources(
      ${target}_module
      PRIVATE
        "${napi_module_dir}/win32/delay-load.c"
    )
  endif()

  target_link_libraries(
    ${target}_module
    PUBLIC
      ${target}
    PRIVATE
      ${target}_import_lib
  )

  set(${result} ${target})

  return(PROPAGATE ${result})
endfunction()
