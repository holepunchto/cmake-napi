#include <assert.h>
#include <node_api.h>

extern int
foo(void);

static napi_value
addon_exports(napi_env env, napi_value exports) {
  napi_status status = napi_create_int32(env, foo(), &exports);
  assert(status == napi_ok);

  return exports;
}

NAPI_MODULE(addon, addon_exports)
