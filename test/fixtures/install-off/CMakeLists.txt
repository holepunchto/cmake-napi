cmake_minimum_required(VERSION 3.25)

find_package(cmake-napi REQUIRED PATHS node_modules/cmake-napi)

project(napi_install_off C)

add_napi_module(addon INSTALL OFF)

target_sources(
  ${addon}
  PRIVATE
    binding.c
)
