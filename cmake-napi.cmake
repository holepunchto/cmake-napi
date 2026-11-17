include_guard()

set(napi_module_dir "${CMAKE_CURRENT_LIST_DIR}")

# Download `url` to `path`, failing the configure if the download fails. The
# file is only moved into place once complete, so an existing `path` is always
# a complete download.
function(napi_download url path)
  file(DOWNLOAD "${url}" "${path}.part" STATUS status)

  list(GET status 0 code)

  if(NOT code EQUAL 0)
    list(GET status 1 error)

    file(REMOVE "${path}.part")

    message(FATAL_ERROR "Could not download ${url}: ${error}")
  endif()

  file(RENAME "${path}.part" "${path}")
endfunction()

function(node_lts_version result)
  get_property(version GLOBAL PROPERTY napi_lts_version)

  if(version)
    set(${result} ${version})

    return(PROPAGATE ${result})
  endif()

  set(index "${CMAKE_BINARY_DIR}/_napi/node-index.json")

  napi_download("https://nodejs.org/download/release/index.json" "${index}")

  file(READ "${index}" releases)

  string(JSON len LENGTH "${releases}")

  math(EXPR last "${len} - 1")

  # Releases are ordered by version, newest first, and carry a codename rather
  # than `false` in their `lts` field once they enter long-term support. The
  # first such release is therefore the latest release of the active LTS line.
  foreach(i RANGE ${last})
    string(JSON type TYPE "${releases}" ${i} "lts")

    if(type STREQUAL "STRING")
      string(JSON version GET "${releases}" ${i} "version")

      string(REGEX REPLACE "^v" "" ${result} "${version}")

      set_property(GLOBAL PROPERTY napi_lts_version ${${result}})

      return(PROPAGATE ${result})
    endif()
  endforeach()

  message(FATAL_ERROR "No Node.js LTS release found")
endfunction()

function(download_node_headers result)
  set(one_value_keywords
    DESTINATION
    VERSION
    IMPORT_FILE
  )

  cmake_parse_arguments(
    PARSE_ARGV 1 ARGV "" "${one_value_keywords}" ""
  )

  if(NOT ARGV_DESTINATION)
    set(ARGV_DESTINATION "${CMAKE_BINARY_DIR}/_napi")
  endif()

  if(NOT ARGV_VERSION)
    set(ARGV_VERSION "24.20.0")
  endif()

  if(ARGV_VERSION STREQUAL "LTS")
    node_lts_version(ARGV_VERSION)
  endif()

  napi_target(target)

  set(version "v${ARGV_VERSION}")

  set(output "${ARGV_DESTINATION}/node-${version}")

  if(NOT EXISTS "${output}")
    set(archive "${ARGV_DESTINATION}/node-${version}-headers.tar.gz")

    napi_download(
      "https://nodejs.org/download/release/${version}/node-${version}-headers.tar.gz"
      "${archive}"
    )

    # Extract to a staging directory first so that `output` only ever exists
    # once fully extracted.
    set(staging "${ARGV_DESTINATION}/.node-${version}")

    file(REMOVE_RECURSE "${staging}")

    file(ARCHIVE_EXTRACT
      INPUT "${archive}"
      DESTINATION "${staging}"
    )

    file(RENAME "${staging}/node-${version}" "${output}")

    file(REMOVE_RECURSE "${staging}" "${archive}")
  endif()

  set(import_file ${ARGV_IMPORT_FILE})

  if(import_file)
    if(target MATCHES "win32")
      napi_arch(arch)

      set(lib "${output}/lib/${arch}/node.lib")

      if(NOT EXISTS "${lib}")
        napi_download(
          "https://nodejs.org/download/release/${version}/win-${arch}/node.lib"
          "${lib}"
        )
      endif()

      set(${import_file} "${lib}")
    else()
      set(${import_file} ${import_file}-NOTFOUND)
    endif()
  endif()

  set(${result} "${output}/include/node")

  return(PROPAGATE ${result} ${import_file})
endfunction()

function(napi_platform result)
  cmake_parse_arguments(
    PARSE_ARGV 1 ARGV "HOST" "" ""
  )

  if(ARGV_HOST)
    set(platform ${CMAKE_HOST_SYSTEM_NAME})
  else()
    set(platform ${CMAKE_SYSTEM_NAME})

    if(NOT platform)
      set(platform ${CMAKE_HOST_SYSTEM_NAME})
    endif()
  endif()

  string(TOLOWER "${platform}" platform)

  if(platform MATCHES "darwin|ios|linux|android|freertos")
    set(${result} ${platform})
  elseif(platform MATCHES "windows")
    set(${result} "win32")
  else()
    set(${result} "unknown")
  endif()

  return(PROPAGATE ${result})
endfunction()

function(napi_arch result)
  cmake_parse_arguments(
    PARSE_ARGV 1 ARGV "HOST" "" ""
  )

  if(ARGV_HOST)
    set(arch ${CMAKE_HOST_SYSTEM_PROCESSOR})
  else()
    if(APPLE AND CMAKE_OSX_ARCHITECTURES)
      set(arch ${CMAKE_OSX_ARCHITECTURES})
    elseif(MSVC AND CMAKE_GENERATOR_PLATFORM)
      set(arch ${CMAKE_GENERATOR_PLATFORM})
    elseif(ANDROID AND CMAKE_ANDROID_ARCH_ABI)
      set(arch ${CMAKE_ANDROID_ARCH_ABI})
    else()
      set(arch ${CMAKE_SYSTEM_PROCESSOR})
    endif()

    # The host processor says nothing about the target when cross compiling, so
    # report an unknown arch rather than a wrong one.
    if(NOT arch AND NOT CMAKE_CROSSCOMPILING)
      set(arch ${CMAKE_HOST_SYSTEM_PROCESSOR})
    endif()
  endif()

  string(TOLOWER "${arch}" arch)

  if(arch MATCHES "arm64|aarch64")
    set(${result} "arm64")
  elseif(arch MATCHES "armv8m")
    set(${result} "armv8m")
  elseif(arch MATCHES "armv7-a|armeabi-v7a")
    set(${result} "arm")
  elseif(arch MATCHES "x64|x86_64|amd64")
    set(${result} "x64")
  elseif(arch MATCHES "x86|i386|i486|i586|i686")
    set(${result} "ia32")
  elseif(arch MATCHES "riscv32")
    set(${result} "riscv32")
  else()
    set(${result} "unknown")
  endif()

  return(PROPAGATE ${result})
endfunction()

function(napi_simulator result)
  cmake_parse_arguments(
    PARSE_ARGV 1 ARGV "HOST" "" ""
  )

  if(ARGV_HOST)
    set(sysroot "")
  else()
    set(sysroot ${CMAKE_OSX_SYSROOT})
  endif()

  if(sysroot MATCHES "iPhoneSimulator")
    set(${result} YES)
  else()
    set(${result} NO)
  endif()

  return(PROPAGATE ${result})
endfunction()

function(napi_environment result)
  cmake_parse_arguments(
    PARSE_ARGV 1 ARGV "HOST" "" ""
  )

  set(environment "")

  if(NOT ARGV_HOST)
    if(APPLE AND CMAKE_OSX_SYSROOT MATCHES "iPhoneSimulator")
      set(environment "simulator")
    elseif(LINUX AND CMAKE_C_COMPILER_TARGET MATCHES "-linux-(musl(sf)?)")
      set(environment "${CMAKE_MATCH_1}")
    endif()
  endif()

  set(${result} ${environment})

  return(PROPAGATE ${result})
endfunction()

function(napi_target result)
  cmake_parse_arguments(
    PARSE_ARGV 1 ARGV "HOST" "" ""
  )

  if(ARGV_HOST)
    set(host HOST)
  else()
    set(host)
  endif()

  napi_platform(platform ${host})
  napi_arch(arch ${host})
  napi_environment(environment ${host})

  set(target ${platform}-${arch})

  if(environment)
    set(target ${target}-${environment})
  endif()

  set(${result} ${target})

  return(PROPAGATE ${result})
endfunction()

function(napi_module_target directory result)
  set(one_value_keywords
    NAME
    VERSION
    HASH
  )

  cmake_parse_arguments(
    PARSE_ARGV 2 ARGV "" "${one_value_keywords}" ""
  )

  set(package_path package.json)

  cmake_path(ABSOLUTE_PATH directory NORMALIZE)

  cmake_path(ABSOLUTE_PATH package_path BASE_DIRECTORY "${directory}" NORMALIZE)

  file(READ "${package_path}" package)

  string(JSON name GET "${package}" "name")

  if(name MATCHES "__")
    message(FATAL_ERROR "Package name '${name}' is invalid")
  endif()

  string(REGEX REPLACE "/" "__" name ${name})
  string(REGEX REPLACE "^@" "" name ${name})

  string(JSON version GET "${package}" "version")

  string(SHA256 hash "napi ${package_path}")

  string(SUBSTRING "${hash}" 0 8 hash)

  set(${result} "${name}-${version}-${hash}")

  if(ARGV_NAME)
    set(${ARGV_NAME} ${name} PARENT_SCOPE)
  endif()

  if(ARGV_VERSION)
    set(${ARGV_VERSION} ${version} PARENT_SCOPE)
  endif()

  if(ARGV_HASH)
    set(${ARGV_HASH} ${hash} PARENT_SCOPE)
  endif()

  return(PROPAGATE ${result})
endfunction()

function(add_napi_module result)
  set(one_value_keywords
    NODE_VERSION
  )

  set(multi_value_keywords
    INSTALL
  )

  cmake_parse_arguments(
    PARSE_ARGV 1 ARGV "" "${one_value_keywords}" "${multi_value_keywords}"
  )

  if(ARGV_NODE_VERSION)
    set(node_version VERSION "${ARGV_NODE_VERSION}")
  else()
    set(node_version)
  endif()

  if(ARGV_INSTALL STREQUAL "OFF")
    set(install OFF)
    set(ARGV_INSTALL)
  else()
    set(install ON)
  endif()

  download_node_headers(
    node_headers ${node_version} IMPORT_FILE node_lib
  )

  napi_module_target("." target NAME name VERSION version)

  string(REGEX MATCH "^[0-9]+" major "${version}")

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

  napi_target(host)

  if(host MATCHES "ios")
    return(PROPAGATE ${result})
  endif()

  # FreeRTOS has no dynamic loader, so addons are only ever linked statically
  # from the object library.
  if(host MATCHES "^freertos-")
    set_target_properties(
      ${target}
      PROPERTIES
      POSITION_INDEPENDENT_CODE OFF
    )

    return(PROPAGATE ${result})
  endif()

  add_library(${target}_module SHARED)

  if(APPLE)
    set(${target}_rpath "@loader_path/${name}")
  elseif(LINUX)
    set(${target}_rpath "$ORIGIN/${name}")
  else()
    set(${target}_rpath "")
  endif()

  set_target_properties(
    ${target}_module
    PROPERTIES

    OUTPUT_NAME ${name}
    PREFIX ""
    SUFFIX ".node"
    IMPORT_PREFIX ""
    IMPORT_SUFFIX ".node.lib"

    # Don't set a shared library name to allow loading the resulting library as
    # a plugin.
    NO_SONAME ON

    # Set the runpath of the addon to support loading of runtime dependencies
    # located in a named directory next to the addon prebuilds.
    INSTALL_RPATH "${${target}_rpath}"
    BUILD_WITH_INSTALL_RPATH ON

    # Set the Mach-O compatibility versions for macOS and iOS. This is mostly
    # for debugging purposes.
    MACHO_CURRENT_VERSION ${version}
    MACHO_COMPATIBILITY_VERSION ${major}
  )

  target_link_libraries(
    ${target}_module
    PRIVATE
      ${target}
  )

  if(host MATCHES "win32")
    add_executable(${target}_import_library IMPORTED)

    set_target_properties(
      ${target}_import_library
      PROPERTIES
      ENABLE_EXPORTS ON
      IMPORTED_IMPLIB "${node_lib}"
    )

    if(NOT TARGET napi_delay_load)
      add_library(napi_delay_load STATIC)

      target_sources(
        napi_delay_load
        PRIVATE
          "${napi_module_dir}/win32/delay-load.c"
      )

      target_link_libraries(
        napi_delay_load
        INTERFACE
          delayimp
      )

      target_link_options(
        napi_delay_load
        INTERFACE
          /DELAYLOAD:node.exe
      )
    endif()

    target_link_libraries(
      ${target}_module
      PRIVATE
        ${target}_import_library
      PUBLIC
        napi_delay_load
    )
  else()
    target_link_options(
      ${target}_module
      PRIVATE
        -Wl,-undefined,dynamic_lookup
    )
  endif()

  restrict_napi_module_exports(${target})

  if(NOT install)
    return(PROPAGATE ${result})
  endif()

  install(
    FILES $<TARGET_FILE:${target}_module>
    DESTINATION ${host}
    RENAME ${name}.node
  )

  while(TRUE)
    list(LENGTH ARGV_INSTALL len)

    if(len LESS 2)
      break()
    endif()

    list(POP_FRONT ARGV_INSTALL type value)

    if(type MATCHES "TARGET")
      get_target_property(target_type ${value} TYPE)

      if(target_type MATCHES "SHARED_LIBRARY" AND NOT WIN32)
        install(
          FILES $<TARGET_FILE:${value}>
          DESTINATION ${host}/${name}
          RENAME $<TARGET_SONAME_FILE_NAME:${value}>
        )
      else()
        install(
          FILES $<TARGET_FILE:${value}>
          DESTINATION ${host}/${name}
        )
      endif()
    endif()
  endwhile()

  return(PROPAGATE ${result})
endfunction()

# Export only the symbols that Node.js looks up when loading the addon `target`
# from its shared library.
function(restrict_napi_module_exports target)
  # The Node.js headers declare the loader symbols with `__declspec(dllexport)`,
  # so a DLL exports nothing else to begin with.
  if(WIN32)
    return()
  endif()

  set(base "${CMAKE_CURRENT_BINARY_DIR}/${target}")

  set(symbols
    napi_register_module_v*
    node_api_module_get_api_version_v*
    node_register_module_v*
  )

  if(APPLE)
    set(exports_file "${base}.exp")

    list(TRANSFORM symbols PREPEND "_")
    list(JOIN symbols "\n" symbols)

    file(CONFIGURE OUTPUT "${exports_file}" CONTENT "${symbols}\n" @ONLY)

    target_link_options(
      ${target}_module
      PRIVATE
        "-Wl,-exported_symbols_list,${exports_file}"
    )
  else()
    set(exports_file "${base}.map")

    list(TRANSFORM symbols PREPEND "    ")
    list(JOIN symbols ";\n" symbols)

    file(CONFIGURE OUTPUT "${exports_file}" CONTENT "{\n  global:\n${symbols};\n\n  local:\n    *;\n};\n" @ONLY)

    target_link_options(
      ${target}_module
      PRIVATE
        "-Wl,--version-script=${exports_file}"
    )
  endif()

  set_property(
    TARGET ${target}_module
    APPEND
    PROPERTY LINK_DEPENDS "${exports_file}"
  )
endfunction()
