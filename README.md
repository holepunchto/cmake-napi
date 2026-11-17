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

Download the Node.js headers for `VERSION`, which may be `LTS` to track the active LTS line rather than a fixed version. Headers already downloaded to `DESTINATION` are reused.

#### `napi_platform(<result> [HOST])`

Write the current compilation target platform to the `<result>` variable. Pass the `HOST` option to write the build host platform instead.

#### `napi_arch(<result> [HOST])`

Write the current compilation target architecture to the `<result>` variable. Pass the `HOST` option to write the build host architecture instead.

#### `napi_simulator(<result> [HOST])`

Write whether or not the current compilation target is a simulator to the `<result>` variable. Pass the `HOST` option to write whether the build host is a simulator instead, which it never is.

#### `napi_environment(<result> [HOST])`

Write the current compilation target environment to the `<result>` variable. Pass the `HOST` option to write the build host environment instead.

#### `napi_target(<result> [HOST])`

Write the current compilation target to the `<result>` variable. Pass the `HOST` option to write the build host target instead.

#### `napi_module_target(<directory> <result> [NAME <var>] [VERSION <var>] [HASH <var>])`

#### `add_napi_module(<result> [NODE_VERSION <version>] [INSTALL OFF | INSTALL [TARGET <target>]...])`

Add a Node-API module, downloading the Node.js headers for `NODE_VERSION`. The module exports only the symbols that Node.js needs to load it.

Pass `INSTALL OFF` to add no install rules for the module, such as when it's only used by tests. To ship shared libraries that the module depends on, pass them as `INSTALL TARGET <target>`. They're installed to a directory named after the module, next to the module itself, which the module looks up at runtime. On Windows, also link the module with `/DELAYLOAD:<library>.dll` for each such library, as PE has no runpath and the libraries are instead found by the delay load hook.

## License

Apache-2.0
