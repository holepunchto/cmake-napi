// Delay loader implementation for Windows. This is used to support loading
// native addons from binaries that don't declare themselves as "node.exe".
//
// See https://learn.microsoft.com/en-us/cpp/build/reference/understanding-the-helper-function

#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif

#include <windows.h> // Must come first

#include <delayimp.h>
#include <string.h>

static inline HMODULE
napi__module_main (void) {
  static HMODULE main = NULL;

  if (main == NULL) main = GetModuleHandle(NULL);

  return main;
}

static inline int
napi__string_equals (LPCSTR a, LPCSTR b) {
  return _stricmp(a, b) == 0;
}

static FARPROC WINAPI
napi__delay_load (unsigned event, PDelayLoadInfo info) {
  switch (event) {
  case dliNotePreLoadLibrary:
    LPCSTR dll = info->szDll;

    if (napi__string_equals(dll, "node.exe")) {
      return (FARPROC) napi__module_main();
    }

    return NULL;

  default:
    return NULL;
  }

  return NULL;
}

const PfnDliHook __pfnDliNotifyHook2 = napi__delay_load;

const PfnDliHook __pfnDliFailureHook2 = napi__delay_load;
