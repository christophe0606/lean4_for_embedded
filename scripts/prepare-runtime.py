#!/usr/bin/env python3
"""Copy the pinned runtime into the build tree and apply checked platform edits."""
import pathlib
import sys
src, dst = map(pathlib.Path, sys.argv[1:])
import difflib
import json
import subprocess
root = pathlib.Path(__file__).resolve().parent.parent
pin = json.loads((root / 'upstream.json').read_text(encoding='utf-8'))
commit = subprocess.check_output(['git', '-C', str(src), 'rev-parse', 'HEAD'], text=True).strip()
if commit != pin['commit']:
    sys.exit('error: upstream Lean revision does not match upstream.json')
subprocess.run(['git', '-C', str(src), 'diff', '--quiet', 'HEAD', '--', 'src/runtime', 'src/include', 'src/util'], check=True)
original = {}
contents = {}
for folder in ('runtime', 'util', 'include'):
    for source in (src / 'src' / folder).rglob('*'):
        if source.is_file():
            relative = source.relative_to(src / 'src')
            original[relative] = source.read_text(encoding='utf-8')
contents.update(original)

def read(path):
    return contents[path.relative_to(dst)]

def write(path, text):
    contents[path.relative_to(dst)] = text

def replace_checked(relative, old, new):
    path = dst / relative
    text = read(path)
    assert text.count(old) == 1, f'unexpected upstream content in {relative}'
    write(path, text.replace(old, new))

p = dst / 'runtime/thread.cpp'
s = read(p)
old = '#else\n#include <pthread.h>\n#endif'
assert s.count(old) == 1
write(p, s.replace(old, '#elif !defined(LEAN_CMSIS)\n#include <pthread.h>\n#endif'))
p = dst / 'runtime/stack_overflow.h'
s = read(p).replace('#ifndef LEAN_WINDOWS', '#if !defined(LEAN_WINDOWS) && !defined(LEAN_CMSIS)')
write(p, s)

p = dst / 'runtime/thread.h'
s = read(p)
s = s.replace('#include <functional>', '#include <functional>\n#include <mutex>')
write(p, s)
p = dst / 'runtime/object.cpp'
s = read(p)
old = '        lock.wait(1);'
assert s.count(old) == 1
s = s.replace(old, '#ifdef LEAN_CMSIS\n        while (lock.load(std::memory_order_relaxed) == 1) this_thread::yield();\n#else\n' + old + '\n#endif')
old = '    lock.notify_one();'
assert s.count(old) == 1
s = s.replace(old, '#ifndef LEAN_CMSIS\n' + old + '\n#endif')
write(p, s)

p = dst / 'runtime/stackinfo.cpp'
s = read(p).replace('#if defined(LEAN_WINDOWS)', '#if defined(LEAN_CMSIS)\n    // CMSIS supplies stack bounds instead of POSIX rlimit.\n#elif defined(LEAN_WINDOWS)', 1)
old = '#if defined(LEAN_WINDOWS)\nsize_t get_stack_size(bool main)'
assert s.count(old) == 1
s = s.replace(old, '#if defined(LEAN_CMSIS)\nextern "C" size_t lean_cmsis_stack_size();\nsize_t get_stack_size(bool) { return lean_cmsis_stack_size(); }\n#elif defined(LEAN_WINDOWS)\nsize_t get_stack_size(bool main)')
write(p, s)

p = dst / 'runtime/thread.h'
s = read(p)
old = '#if defined(LEAN_MULTI_THREAD)'
assert s.count(old) == 1
s = s.replace(old, '#if defined(LEAN_CMSIS) && defined(LEAN_MULTI_THREAD)\n#define LEAN_THREAD_LOCAL thread_local\n#include "cmsis_thread.h"\n#elif defined(LEAN_MULTI_THREAD)')
write(p, s)
p = dst / 'runtime/thread.cpp'
s = read(p)
old = '#if defined(LEAN_WINDOWS)\n/* Windows version */'
assert s.count(old) == 1
s = s.replace(old, '#if defined(LEAN_CMSIS)\n#include "cmsis_lthread.inc"\n#elif defined(LEAN_WINDOWS)\n/* Windows version */')
s = s.replace('#include <lean/config.h>', '#include <lean/config.h>\n#ifdef LEAN_CMSIS\nextern "C" void lean_cmsis_tls_cleanup();\n#endif')
write(p, s)
p = dst / 'runtime/object.cpp'
s = read(p).replace('std::chrono::steady_clock', 'lean::cmsis_clock')
write(p, s)
# Firmware uses C stdio for diagnostics. In particular, merely including
# <iostream> initializes global C++ streams and pulls locale facets into MRAM.
for relative in ('runtime/debug.h', 'runtime/thread.h', 'runtime/mpz.h',
                 'runtime/stackinfo.cpp', 'runtime/thread.cpp'):
    replace_checked(relative, '#include <iostream>\n', '')
replace_checked('runtime/thread.cpp', '#include "runtime/sstream.h"\n', '')

p = dst / 'runtime/debug.cpp'
s = read(p)
old = '#include <iostream>\n#include <sstream>\n'
assert s.count(old) == 1
s = s.replace(old, '#include <cstdio>\n')
old = '''    std::cerr << "LEAN ASSERTION VIOLATION\\n";
    std::cerr << "File: " << fileName << "\\n";
    std::cerr << "Line: " << line << "\\n";
    std::cerr << condition << "\\n";
    std::cerr.flush();'''
assert s.count(old) == 1
s = s.replace(old, '''    std::fprintf(stderr, "LEAN ASSERTION VIOLATION\\nFile: %s\\nLine: %d\\n%s\\n",
                 fileName, line, condition);
    std::fflush(stderr);''')
start = s.index('void invoke_debugger() {')
end = s.index('// LCOV_EXCL_STOP', start)
s = s[:start] + 'void invoke_debugger() {\n    debuggable_exit();\n}\n' + s[end:]
write(p, s)

replace_checked('runtime/object.cpp', '#include <cmath>\n',
                '#include <cmath>\n#include <cstdio>\n')
replace_checked('runtime/object.cpp',
                '        std::cerr.write(line, size) << "\\n";',
                '        std::fwrite(line, 1, size, stderr);\n        std::fputc(\'\\n\', stderr);')

# The firmware's non-GMP integer backend already produces decimal digits.
# Build a string from those digits instead of routing it through ostream.
replace_checked('runtime/mpz.h',
                '    LEAN_EXPORT friend std::ostream & operator<<(std::ostream & out, mpz const & v);\n', '')
p = dst / 'runtime/mpz.cpp'
s = read(p)
assert s.count('#include "runtime/sstream.h"\n') == 1
s = s.replace('#include "runtime/sstream.h"\n', '#include <cstdio>\n')
start = s.index('void display(std::ostream & out, __mpz_struct const * v) {')
end = s.index('\n#else\n/***** NON GMP VERSION', start)
s = s[:start] + s[end:]
start = s.index('std::ostream & operator<<(std::ostream & out, mpz const & v) {')
end = s.index('\n#endif\n\n\nstd::string mpz::to_string()', start)
s = s[:start] + s[end:]
start = s.index('std::string mpz::to_string() const {')
end = s.index('\n}', start) + 2
s = s[:start] + '''std::string mpz::to_string() const {
#ifdef LEAN_USE_GMP
    std::string result(mpz_sizeinbase(m_val, 10) + 2, '\\0');
    mpz_get_str(result.data(), 10, m_val);
    result.resize(std::strlen(result.c_str()));
    return result;
#else
    buffer<char, 1024> digits;
    digits.resize(11 * m_size, 0);
    char const * text = mpn_to_string(m_digits, m_size, digits.begin(), digits.size());
    return m_sign ? std::string("-") + text : std::string(text);
#endif
}''' + s[end:]
old = 'void print(lean::mpz const & n) { std::cout << n << std::endl; }'
assert s.count(old) == 1
s = s.replace(old, 'void print(lean::mpz const & n) { std::printf("%s\\n", n.to_string().c_str()); }')
write(p, s)

# Only the desktop runtime needs the stream-based exception constructor.
replace_checked('runtime/exception.h', 'class sstream;\n', '')
replace_checked('runtime/exception.h', '    throwable(sstream const & strm);\n', '')
replace_checked('runtime/exception.h', '    exception(sstream const & strm):throwable(strm) {}\n', '')
p = dst / 'runtime/exception.cpp'
s = read(p)
assert s.count('#include <sstream>\n') == 1
assert s.count('#include "runtime/sstream.h"\n') == 1
assert s.count('throwable::throwable(sstream const & strm):m_msg(strm.str()) {}\n') == 1
s = s.replace('#include <sstream>\n', '').replace('#include "runtime/sstream.h"\n', '')
s = s.replace('throwable::throwable(sstream const & strm):m_msg(strm.str()) {}\n', '')
start = s.index('stack_space_exception::stack_space_exception(char const * component_name):')
end = s.index('char const * heartbeat_exception::what()', start)
s = s[:start] + '''stack_space_exception::stack_space_exception(char const * component_name):
    m_msg(std::string("deep recursion was detected at '") + component_name +
          "' (potential solution: increase elaboration stack size using the `lean --tstack` flag). "
          "This flag can be set in the `weakLeanArgs` field of the Lake configuration. "
          "Further details are available in the Lean reference manual at " + LEAN_MANUAL_ROOT +
          "find/?domain=Verso.Genre.Manual.section&name=lake-config-toml") {
}

memory_exception::memory_exception(char const * component_name):
    m_msg(std::string("excessive memory consumption detected at '") + component_name +
          "' (potential solution: increase memory consumption threshold)") {
}

''' + s[end:]
write(p, s)
# Keep platform-independent IO primitives verbatim from the pinned upstream file.
# Desktop files/processes/libuv are separate capabilities, not successful stubs.
s = (src / 'src/runtime/io.cpp').read_text(encoding='utf-8')
start = s.index('// ST ref primitives')
end = s.index('\nvoid initialize_io()')
clock_start = s.index('/* monoMsNow : BaseIO Nat */')
clock_end = s.index('/* getRandomBytes', clock_start)
initial_start = s.index('static bool g_initializing = true;')
initial_end = s.index('static obj_res mk_file_not_found_error', initial_start)
prefix = '''/* Extracted from Lean src/runtime/io.cpp, Apache-2.0.
 * Copyright (c) 2018 Microsoft Corporation. All rights reserved. */
#include <lean/lean.h>
#include "runtime/object.h"
#include "runtime/object_ref.h"
#include "runtime/option_ref.h"
#include "runtime/io.h"
#include "runtime/thread.h"
namespace lean {
'''
portable = prefix + s[initial_start:initial_end] + s[clock_start:clock_end] + s[start:end] + '\n}\n'
portable = portable.replace('std::chrono::steady_clock', 'lean::cmsis_clock')
contents[pathlib.Path('runtime/cmsis_portable_io.cpp')] = portable

diff = []
for relative, value in contents.items():
    path = dst / relative
    path.parent.mkdir(parents=True, exist_ok=True)
    if not path.exists() or path.read_text(encoding='utf-8') != value:
        path.write_text(value, encoding='utf-8')
    if relative in original and value != original[relative]:
        diff.extend(difflib.unified_diff(original[relative].splitlines(True), value.splitlines(True),
          fromfile='a/src/' + str(relative), tofile='b/src/' + str(relative)))
patch = ''.join(diff)
(dst / 'changes.patch').write_text(patch, encoding='utf-8')
# Optional standard-console support keeps upstream stream TLS and handle code.
io = (src / 'src/runtime/io.cpp').read_text(encoding='utf-8')
stream_start = io.index('static lean_external_class * g_io_handle_external_class')
stream_end = io.index('/* Translates a CRT', stream_start)
streams = io[stream_start:stream_end]
# Initialization is lazy, so linking the core runtime never forces Init.System.IO.
for name in ('lean_get_stdin()', 'lean_get_stdout()', 'lean_get_stderr()',
             'lean_get_set_stdin(obj_arg h)', 'lean_get_set_stdout(obj_arg h)', 'lean_get_set_stderr(obj_arg h)'):
    streams = streams.replace(name + ' {', name + ' {\n    ensure_console();')
handle_start = io.index('/* Handle.isTty')
handle_end = io.index('/* Std.Time.Timestamp.now', handle_start)
handles = io[handle_start:handle_end]
# Truncation is a filesystem facility, not a console operation.
a = handles.index('/* Handle.truncate')
b = handles.index('/* Handle.read', a)
handles = handles[:a] + handles[b:]
init_start = io.index('void initialize_io()')
init_end = io.index('\nvoid finalize_io()', init_start)
initializer = io[init_start:init_end].replace('void initialize_io()', 'void initialize_console()')
a = initializer.index('#if !defined(LEAN_WINDOWS)')
initializer = initializer[:a] + '}\n'
console = prefix.replace('#include <lean/lean.h>', '#include <lean/lean.h>\n#include <cstdio>\n#include <cerrno>\n#include <unistd.h>')
console += 'void ensure_console();\n' + streams + handles + initializer + '\n}\n'
p = dst / 'runtime/cmsis_console_io.cpp'
if not p.exists() or p.read_text(encoding='utf-8') != console:
    p.write_text(console, encoding='utf-8')
