# cmake-napi

Node-API utilities for CMake.

```
npm i cmake-napi
```

```cmake
find_package(cmake-napi REQUIRED PATHS node_modules/cmake-napi)
```

## API

#### `node_lts_version(<result>)`

Resolve the latest release of the active Node.js LTS line.

#### `download_node_headers(<result> [DESTINATION <directory>] [VERSION <version>] [IMPORT_FILE <result>])`

Download the Node.js headers for `VERSION`, which may be `LTS` to track the
active LTS line rather than a fixed version.

#### `napi_platform(<result>)`

#### `napi_arch(<result>)`

#### `napi_environment(<result>)`

#### `napi_target(<result>)`

#### `napi_module_target(<directory> <result> [NAME <var>] [VERSION <var>] [HASH <var>])`

#### `add_napi_module(<result>)`

## License

Apache-2.0
