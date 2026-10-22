#!/usr/bin/env python3
"""Fetch just the exact upstream Lean release; never rebuild the host compiler."""
import json
from pathlib import Path
import subprocess
import sys
root = Path(__file__).resolve().parent.parent
pin = json.loads((root / 'upstream.json').read_text())
destination = root / '.reference/lean4'
if not destination.exists():
    destination.parent.mkdir(parents=True, exist_ok=True)
    subprocess.run(['git', 'clone', '--depth', '1', '--branch', pin['tag'],
                    pin['repository'], str(destination)], check=True)
commit = subprocess.check_output(['git', '-C', str(destination), 'rev-parse', 'HEAD'], text=True).strip()
if commit != pin['commit']:
    sys.exit('Wrong Lean source revision; preserve your checkout and select the pinned upstream release.')
subprocess.run(['git', '-C', str(destination), 'diff', '--exit-code', '--quiet', 'HEAD'], check=True)
print('Verified Lean ' + pin['version'] + ' source at ' + commit)
