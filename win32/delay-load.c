// Delay loader implementation for Windows. This is used to support loading
// native addons from binaries that don't declare themselves as "node.exe" as
// well as loading the runtime dependencies of native addons.
//
// See https://learn.microsoft.com/en-us/cpp/build/reference/understanding-the-helper-function

#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif

#include <windows.h> // Must come first

#include <delayimp.h>
#include <stdlib.h>
#include <string.h>

static inline int
napi__string_equals(LPCSTR a, LPCSTR b) {
  return _stricmp(a, b) == 0;
}

static inline int
napi__string_ends_with(LPCSTR a, LPCSTR b) {
  size_t a_len = strlen(a);
  size_t b_len = strlen(b);

  if (b_len > a_len) return 0;

  return napi__string_equals(a + a_len - b_len, b);
}

static HMODULE napi__module_self = NULL;

static inline HMODULE
napi__module_main(void) {
  static HMODULE main = NULL;

  if (main == NULL) main = GetModuleHandle(NULL);

  return main;
}

typedef BOOL(WINAPI *napi__enum_process_modules_fn)(HANDLE process, HMODULE *modules, DWORD size, LPDWORD needed);

// Pin a module so that its handle stays valid for as long as the operating
// system process lives, no matter who else frees it.
static inline HMODULE
napi__module_pin(HMODULE module) {
  if (module == NULL) return NULL;

  HMODULE pinned;

  BOOL ok = GetModuleHandleExW(
    GET_MODULE_HANDLE_EX_FLAG_PIN | GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS,
    (LPCWSTR) module,
    &pinned
  );

  return ok ? pinned : NULL;
}

// The only module exporting Node-API: the binary itself for Node.js and most
// embedders, otherwise a shared library such as `libnode.dll`. Two of them
// means two runtimes, and binding an addon to the wrong one silently mixes
// their state, so prefer failing to load.
static inline HMODULE
napi__module_runtime(void) {
  static HMODULE runtime = NULL;

  if (runtime != NULL) return runtime;

  HMODULE main = napi__module_main();

  if (GetProcAddress(main, "napi_module_register") != NULL) {
    runtime = main;

    return runtime;
  }

  HMODULE kernel32 = GetModuleHandleA("kernel32.dll");

  if (kernel32 == NULL) return NULL;

  // Resolved at run time so no addon carries a static psapi import.
  napi__enum_process_modules_fn enum_process_modules =
    (napi__enum_process_modules_fn) GetProcAddress(kernel32, "K32EnumProcessModules");

  if (enum_process_modules == NULL) return NULL;

  HANDLE process = GetCurrentProcess();

  DWORD needed = 0;

  if (!enum_process_modules(process, NULL, 0, &needed) || needed == 0) return NULL;

  HMODULE *modules = malloc(needed);

  if (modules == NULL) return NULL;

  HMODULE found = NULL;

  if (enum_process_modules(process, modules, needed, &needed)) {
    DWORD len = needed / sizeof(HMODULE);

    for (DWORD i = 0; i < len; i++) {
      if (GetProcAddress(modules[i], "napi_module_register") == NULL) continue;

      if (found != NULL) {
        found = NULL;

        break;
      }

      found = modules[i];
    }
  }

  free(modules);

  if (found == NULL) return NULL;

  runtime = napi__module_pin(found);

  return runtime;
}

static inline HMODULE
napi__module_load(const char *dll) {
  if (napi__module_self == NULL) return NULL;

  CHAR path[MAX_PATH];

  DWORD len = GetModuleFileNameA(napi__module_self, path, MAX_PATH);

  if (napi__string_ends_with(path, ".node")) {
    path[len - 5] = '\0';
  } else {
    char *separator = strrchr(path, '\\');

    if (separator) *separator = '\0';
  }

  strcat_s(path, MAX_PATH, "\\");
  strcat_s(path, MAX_PATH, dll);

  // The libraries installed next to the addon depend on each other by name and
  // PE has no runpath, so the loader is told to resolve whatever it loads here
  // from this directory as well. Without it only the named library is found and
  // its own dependencies fall back to the ambient search order.
  return LoadLibraryExA(
    path,
    NULL,
    LOAD_LIBRARY_SEARCH_DLL_LOAD_DIR | LOAD_LIBRARY_SEARCH_DEFAULT_DIRS
  );
}

static FARPROC WINAPI
napi__delay_load(unsigned event, PDelayLoadInfo info) {
  if (event != dliNotePreLoadLibrary) return NULL;

  LPCSTR dll = info->szDll;

  if (napi__string_equals(dll, "node.exe")) {
    return (FARPROC) napi__module_runtime();
  }

  if (napi__string_ends_with(dll, ".dll")) {
    return (FARPROC) napi__module_load(dll);
  }

  return NULL;
}

const PfnDliHook __pfnDliNotifyHook2 = napi__delay_load;

const PfnDliHook __pfnDliFailureHook2 = napi__delay_load;

BOOL WINAPI
DllMain(HINSTANCE handle, DWORD reason, LPVOID reserved) {
  if (reason == DLL_PROCESS_ATTACH) napi__module_self = handle;

  return TRUE;
}
