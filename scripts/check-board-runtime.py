#!/usr/bin/env python3
"""Run the actual Lean API/registry against deterministic host peripherals."""
from pathlib import Path
import json
import re
import shutil
import subprocess

ROOT = Path(__file__).resolve().parents[1]
BUILD = ROOT / '.build/board-api-runtime'
BUILD.mkdir(parents=True, exist_ok=True)


def run(args, cwd=ROOT):
    result = subprocess.run([str(arg) for arg in args], cwd=cwd, text=True,
                            encoding='utf-8', stdout=subprocess.PIPE,
                            stderr=subprocess.STDOUT)
    if result.returncode:
        raise SystemExit(result.stdout)
    return result.stdout


# An unmodeled native call traps rather than silently claiming success. Generate
# those stubs from the production signatures so all imported modules can link.
mock = (ROOT / 'scripts/tests/board-api-mock.c').read_text(encoding='utf-8')
pattern = re.compile(r'(lean_object\s*\*|uint32_t|uint8_t|size_t)\s*'
                     r'(lean_board_\w+)\s*\(([^)]*)\)')
source = '#include "bridge.h"\n' + mock + '\n'
def signature(result, arguments):
    return re.sub(r'\s', '', result), tuple(
        re.sub(r'\s', '', re.match(r'(lean_object\s*\*|uint32_t|uint8_t|size_t)', arg.strip())[1])
        for arg in arguments.split(',') if arg.strip() not in ('', 'void'))


mocked = {name: signature(result, arguments)
          for result, name, arguments in pattern.findall(mock)}
for path in ROOT.glob('api/c/bridge_*.c'):
    for result, name, arguments in pattern.findall(path.read_text(encoding='utf-8')):
        if name in mocked:
            assert mocked[name] == signature(result, arguments), ('mock ABI mismatch', name)
        else:
            source += f'{result} {name}({arguments}) {{ __builtin_trap(); }}\n'
(BUILD / 'mock.c').write_text(source, encoding='utf-8')
for source_file, object_file in [(BUILD/'mock.c', BUILD/'mock.o'),
                                 (ROOT/'api/c/resource_state.c', BUILD/'registry.o')]:
    run(['lake', 'env', 'leanc', '-c', '-I'+str(ROOT/'api/c'),
         source_file, '-o', object_file])
shutil.copyfile(ROOT/'lean-toolchain', BUILD/'lean-toolchain')
shutil.copyfile(ROOT/'scripts/tests/BoardApiRuntimeTests.lean', BUILD/'BoardApiRuntimeTests.lean')
(BUILD/'lakefile.toml').write_text(
    'name = "board_api_runtime_tests"\nmoreLeanArgs = ["-DwarningAsError=true"]\n'
    '[[require]]\nname = "lean_cmsis"\npath = "../.."\n'
    '[[lean_exe]]\nname = "BoardApiRuntimeTests"\n'
    'moreLinkArgs = ' + json.dumps([str(BUILD/'mock.o'), str(BUILD/'registry.o')]) + '\n',
    encoding='utf-8')
run(['lake', 'build', 'BoardApiRuntimeTests'], cwd=BUILD)
exe = BUILD / '.lake/build/bin/BoardApiRuntimeTests'
if not exe.exists():
    exe = exe.with_suffix('.exe')
print(run([exe]), end='')
