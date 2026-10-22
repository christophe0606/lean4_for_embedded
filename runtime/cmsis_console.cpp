#include <lean/lean.h>
#include "runtime/io.h"
#include "runtime/object.h"
#include <cstdio>
#include <cstring>
#include <cerrno>
namespace lean {
extern "C" lean_object * lean_decode_io_error(int error, lean_object *) {
    return lean_mk_io_error_other_error(error, lean_mk_string(strerror(error)));
}
void initialize_console();
void ensure_console() {
    static bool initialized = (initialize_console(), true);
    (void)initialized;
}
}
