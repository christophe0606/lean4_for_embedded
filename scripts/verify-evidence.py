#!/usr/bin/env python3
"""Check that both current ELF images passed every required FVP test."""
import argparse
import hashlib
import json
from pathlib import Path
import sys
parser = argparse.ArgumentParser()
parser.add_argument('--console', action='store_true', help='Also verify both optional Console profile images')
args = parser.parse_args()
root = Path(__file__).resolve().parent.parent
markers = [
    'PASS: Lean Nat arithmetic',
    'PASS: upstream Task spawn/map/bind/dedicated',
    'PASS: TLS isolation/reuse',
    'PASS: RTX recursive/shared mutexes',
    'PASS: Promise wait/resolve, concurrent heap stress, C++ once guard',
    'PASS: upstream ST.Ref primitives + RTX monotonic clock',
    'PASS: proved SysTick contract + FVP register readback (7 boundaries)',
]
try:
    profiles = ('Debug', 'Console') if args.console else ('Debug',)
    for target in ('Corstone300-GCC', 'Corstone300-CLANG'):
        for profile in profiles:
            label = target + ('-' + profile if profile != 'Debug' else '')
            path = root / '.build/evidence' / (label + '-lean-smoke.json')
            record = json.loads(path.read_text())
            image = root / record['image']
            if image.parent.parent.name != target or image.parent.name != profile or record['returncode'] != 0:
                raise ValueError(label + ': FVP did not complete successfully')
            if record['sha256'] != hashlib.sha256(image.read_bytes()).hexdigest():
                raise ValueError(label + ': evidence belongs to a different ELF; run the current image')
            expected = markers + (['PASS: standard Lean IO.println on RTX'] if profile == 'Console' else [])
            if record['config_sha256'] != hashlib.sha256((root / record['config']).read_bytes()).hexdigest():
                raise ValueError(label + ': FVP configuration changed; run the current configuration')
            missing = [m for m in expected if m not in record['output']]
            if missing or 'FAIL:' in record['output'] or 'Failed to write bytes' in record['output']:
                raise ValueError(label + ': missing or failed test: ' + ', '.join(missing))
            print(label + ': PASS (' + str(len(expected)) + ' checks, ELF SHA-256 ' + record['sha256'] + ')')
except (OSError, KeyError, ValueError) as error:
    sys.exit('Verification failed: ' + str(error))
