#!/usr/bin/env python3
"""Check checked primitives, rejected misuse, and generated FFI signatures."""
from pathlib import Path
import re
import subprocess

ROOT = Path(__file__).resolve().parents[1]

def run(args):
    return subprocess.run(args, cwd=ROOT, text=True, encoding='utf-8',
                          stdout=subprocess.PIPE, stderr=subprocess.STDOUT)

result = run(['lake', 'build', '+Board:c', '+Board.AlifGPIO.LowLevel:c',
              '+Board.PinConfig.LowLevel:c', '+Board.Internal.USART:c',
              '+Board.Internal.PinConfig:c', '+Blinky:c', '+Smoke:c', '+Console:c'])
if result.returncode:
    raise SystemExit(result.stdout)
print('PASS: Board and all demo Lean C facets', flush=True)

prefix = 'module\nprelude\npublic import Board\npublic import Blinky.Board\npublic import Board.PinConfig.LowLevel\n\n'
cases = [
    ('valid', '''
def configure (driver : Board.GPIO.LowLevel.Driver) (pin : UInt32) : Board.HalM Unit := do
  let output ← Board.GPIO.setupOutput driver pin
  output.set true

def gated : Board.HalM Unit := Board.NVIC.runOpen (irq := 7) <|
  Board.NVIC.masked <| Board.NVIC.temporarilyDisabled <|
    Board.NVIC.clearPendingIRQ

def inputPullFirst (driver : Board.GPIO.LowLevel.Driver) (pin : UInt32) : Board.HalM Unit := do
  let ready ← Board.GPIO.LowLevel.setup driver pin
  Board.GPIO.LowLevel.setPullResistor ready .up
  let input ← Board.GPIO.LowLevel.setDirection ready .input
  let _ ← Board.GPIO.LowLevel.getInput input

def inputDirectionFirst (driver : Board.GPIO.LowLevel.Driver) (pin : UInt32) : Board.HalM Unit := do
  let ready ← Board.GPIO.LowLevel.setup driver pin
  let input ← Board.GPIO.LowLevel.setDirection ready .input
  Board.GPIO.LowLevel.setPullResistor input .up
  let _ ← Board.GPIO.LowLevel.getInput input

def outputPreloaded (driver : Board.GPIO.LowLevel.Driver) (pin : UInt32) : Board.HalM Unit := do
  let ready ← Board.GPIO.LowLevel.setup driver pin
  let preloaded ← Board.GPIO.LowLevel.preloadOutput ready false
  let output ← Board.GPIO.LowLevel.setDirection preloaded .output
  Board.GPIO.LowLevel.setOutput output true

def inputToOutput (input : Board.GPIO.Input 1 2) : Board.HalM (Board.GPIO.Output 1 2) := do
  let preloaded ← Board.GPIO.LowLevel.preloadOutput input true
  let _ ← Board.GPIO.LowLevel.getInput preloaded
  Board.GPIO.LowLevel.setDirection preloaded .output

def preservedLatch (output : Board.GPIO.Output 1 2) : Board.HalM (Board.GPIO.Output 1 2) := do
  let input ← Board.GPIO.LowLevel.setDirection output .input
  Board.GPIO.LowLevel.setDirection input .output

def timer (config : Board.SysTick.Config period) : Board.HalM Unit := do
  let acquired ← Board.SysTick.LowLevel.acquire
  let stopped ← Board.SysTick.LowLevel.stop acquired
  let loaded ← Board.SysTick.LowLevel.load stopped config
  let cleared ← Board.SysTick.LowLevel.clear loaded
  let running ← Board.SysTick.LowLevel.start cleared
  let _ ← Board.SysTick.LowLevel.read running

def usartRxFirst (driver : Board.USART.LowLevel.Driver 1 (.configured none none)) :
    Board.HalM (Board.USART.LowLevel.Driver 1 (.configured (some true) (some true))) := do
  let rx ← Board.USART.LowLevel.setReceiver driver true
  Board.USART.LowLevel.setTransmitter rx true

def usartTxFirst (driver : Board.USART.LowLevel.Driver 1 (.configured none none)) :
    Board.HalM (Board.USART.LowLevel.Driver 1 (.configured (some true) (some true))) := do
  let tx ← Board.USART.LowLevel.setTransmitter driver true
  Board.USART.LowLevel.setReceiver tx true

def callbackInput (source : Board.GPIO.LowLevel.InterruptSource 1 2 3)
    (native : Board.AlifGPIO.LowLevel.Source 1 2 3) :
    Board.NVIC.LowLevel.GateM 3 .blocked .disabled
      (Board.AlifGPIO.LowLevel.Interrupt 1 2 3 .enabled) := do
  let ready ← Board.GPIO.LowLevel.setupInterrupt source
  let input ← Board.GPIO.LowLevel.setInterruptDirection ready .input
  Board.GPIO.LowLevel.setInterruptPull input .up
  let falling ← Board.GPIO.LowLevel.setEventTrigger input .falling
  let muted ← Board.AlifGPIO.LowLevel.attach native falling
  let cleared ← Board.AlifGPIO.LowLevel.interruptEoi muted
  let unmasked ← Board.AlifGPIO.LowLevel.unmaskInterrupt cleared
  Board.AlifGPIO.LowLevel.enableInterrupt unmasked

def preparePad (pad : Board.PinConfig.LowLevel.Pad) : Board.HalM Unit := do
  let owned ← Board.PinConfig.LowLevel.claim pad
  Board.PinConfig.LowLevel.set owned ⟨0, by decide⟩ 0
''', None),
    ('unconfigured-output', 'def bad : Board.GPIO.Output 1 2 := ⟨⟨1, 1⟩⟩', 'private'),
    ('wrong-pin', 'def bad (p : Board.GPIO.Output 1 2) : Board.GPIO.Output 1 3 := p', 'mismatch'),
    ('wrong-driver', 'def bad (p : Board.GPIO.Output 1 2) : Board.GPIO.Output 2 2 := p', 'mismatch'),
    ('input-as-output', 'def bad (p : Board.GPIO.Input 1 2) : Board.HalM Unit := Board.GPIO.Output.set p true', 'mismatch'),
    ('missing-setup', 'def bad : Board.HalM Unit := Board.GPIO.LowLevel.setPullResistor 2 .up', 'instance'),
    ('output-before-direction', 'def bad (p : Board.GPIO.LowLevel.Pin 1 2 .ready) : Board.HalM Unit := Board.GPIO.LowLevel.setOutput p true', 'mismatch'),
    ('raw-gpio-not-exported', 'def bad := Board.Internal.Raw.GPIO.setup', 'unknown'),
    ('arbitrary-driver', 'def bad : Board.GPIO.LowLevel.Driver := ⟨1, fun _ => true⟩', 'private'),
    ('arbitrary-event-id', 'def bad := Board.CMSISRTOS.EventFlagsId.borrow 1', 'unknown'),
    ('arbitrary-flags', 'def bad : Board.CMSISRTOS.Flags := ⟨0x80000000⟩', 'private'),
    ('raw-rtos-not-exported', 'def bad := Board.Internal.Raw.CMSISRTOS.eventFlagsDelete', 'unknown'),
    ('systick-load-before-stop', 'def bad (t : Board.SysTick.LowLevel.Timer .acquired) (c : Board.SysTick.Config period) := Board.SysTick.LowLevel.load t c', 'mismatch'),
    ('systick-start-before-clear', 'def bad (t : Board.SysTick.LowLevel.Timer .loaded) := Board.SysTick.LowLevel.start t', 'mismatch'),
    ('systick-reload-running', 'def bad (t : Board.SysTick.LowLevel.Timer .running) (c : Board.SysTick.Config period) := Board.SysTick.LowLevel.load t c', 'mismatch'),
    ('usart-config-before-power', 'def bad (d : Board.USART.LowLevel.Driver 1 .initialized) := Board.USART.LowLevel.configure d 115200', 'mismatch'),
    ('usart-send-before-enable', 'def bad (d : Board.USART.LowLevel.Driver 1 (.configured none (some true))) (b : Board.USART.LowLevel.Buffer) := Board.USART.LowLevel.send d b 1', 'mismatch'),
    ('usart-poweroff-active', 'def bad (d : Board.USART.LowLevel.Transfer 1 (some true) (some true) .send) := Board.USART.LowLevel.powerOff d', 'mismatch'),
    ('usart-poweroff-unknown', 'def bad (d : Board.USART.LowLevel.Driver 1 (.configured none none)) := Board.USART.LowLevel.powerOff d', 'mismatch'),
    ('usart-arbitrary-buffer', 'def bad : Board.USART.LowLevel.Buffer := ⟨1, 8, ⟨1, 1⟩⟩', 'private'),
    ('wrong-irq', 'def bad (a : Board.NVIC.GateM 1 .blocked .disabled Unit) : Board.NVIC.GateM 2 .blocked .disabled Unit := a', 'mismatch'),
    ('missing-mask', 'def bad : Board.HalM Unit := Board.NVIC.runOpen (Board.NVIC.clearPendingIRQ (irq := 1))', 'mismatch'),
    ('missing-line-disable', 'def bad : Board.HalM Unit := Board.NVIC.runOpen (Board.NVIC.masked (Board.NVIC.clearPendingIRQ (irq := 1)))', 'mismatch'),
    ('unrestricted-gate-lift', 'def bad := Board.NVIC.GateM.fromHal', 'unknown'),
    ('raw-cpu-not-exported', 'def bad := Board.Internal.Raw.CPU.enableIRQ', 'unknown'),
    ('callback-missing-gates', 'def bad (s : Board.GPIO.LowLevel.InterruptSource 1 2 3) := Board.NVIC.runOpen (Board.GPIO.LowLevel.setupInterrupt s)', 'mismatch'),
    ('button-as-led', 'def bad (p : Blinky.GPIO.Output .center) : Unit := ()', 'mismatch'),
    ('invalid-systick-config', 'def bad : Board.SysTick.Config 1 := { reload := ⟨0, by decide⟩, positive := by decide, exactPeriod := rfl }', 'false'),
    ('unmask-before-eoi', 'def bad (i : Board.AlifGPIO.LowLevel.Interrupt 1 2 3 .muted) := Board.AlifGPIO.LowLevel.unmaskInterrupt i', 'mismatch'),
    ('enable-before-unmask', 'def bad (i : Board.AlifGPIO.LowLevel.Interrupt 1 2 3 .cleared) := Board.AlifGPIO.LowLevel.enableInterrupt i', 'mismatch'),
    ('trigger-before-input', 'def bad (p : Board.GPIO.LowLevel.InterruptPin 1 2 3 .ready false) := Board.GPIO.LowLevel.setEventTrigger p .falling', 'mismatch'),
    ('wrong-interrupt-source', 'def bad (s : Board.AlifGPIO.LowLevel.Source 1 2 3) (p : Board.GPIO.LowLevel.InterruptPin 1 4 3 .input true) := Board.AlifGPIO.LowLevel.attach s p', 'mismatch'),
    ('forged-pad', 'def bad : Board.PinConfig.LowLevel.Pad := ⟨1, 2, 0, 2, fun _ => true⟩', 'private'),
    ('output-direction-before-preload', 'def bad (p : Board.GPIO.LowLevel.Pin 1 2 .ready) := Board.GPIO.LowLevel.setDirection p .output', 'false'),
    ('input-output-without-preload', 'def bad (p : Board.GPIO.Input 1 2) := Board.GPIO.LowLevel.setDirection p .output', 'false'),
    ('preload-after-output-direction', 'def bad (p : Board.GPIO.Output 1 2) := Board.GPIO.LowLevel.preloadOutput p false', 'false'),
    ('discarded-preload', '''def bad (d : Board.GPIO.LowLevel.Driver) : Board.HalM Unit := do
  let ready ← Board.GPIO.LowLevel.setup d 2
  let _ ← Board.GPIO.LowLevel.preloadOutput ready false
  let _ ← Board.GPIO.LowLevel.setDirection ready .output
  pure ()''', 'false'),
    ('interrupt-output-bypass', 'def bad (p : Board.GPIO.LowLevel.InterruptPin 1 2 3 .ready false) := Board.GPIO.LowLevel.setInterruptDirection p .output', 'false'),
]

directory = ROOT / '.build/board-api-checks'
directory.mkdir(parents=True, exist_ok=True)
for name, source, failure in cases:
    path = directory / (name.replace('-', '_') + '.lean')
    path.write_text(prefix + source + '\n', encoding='utf-8')
    result = run(['lake', 'env', 'lean', '-DwarningAsError=true', str(path)])
    if failure is None:
        assert result.returncode == 0, (name, result.stdout)
    else:
        assert result.returncode != 0 and failure in result.stdout.lower(), (name, result.stdout)
    print('PASS:', name, flush=True)

# Compare the compiler's actual extern declarations with C definitions. This
# catches width, boxing and Unit/IO ABI errors that elaboration cannot detect.
pattern = re.compile(r'(lean_object\s*\*|uint32_t|uint8_t|size_t)\s*'
                     r'(lean_(?:board|blinky)_\w+)\s*\(([^)]*)\)')


def signature(result, arguments):
    types = []
    for arg in arguments.split(','):
        arg = arg.strip()
        if not arg or arg == 'void':
            continue
        match = re.match(r'(lean_object\s*\*|uint32_t|uint8_t|size_t)', arg)
        assert match, arg
        types.append(re.sub(r'\s', '', match[1]))
    return re.sub(r'\s', '', result), tuple(types)


definitions = {}
for path in [*ROOT.glob('api/c/bridge_*.c'), ROOT/'examples/blinky/platform.c']:
    for ret, name, args in pattern.findall(path.read_text(encoding='utf-8')):
        assert name not in definitions, name
        definitions[name] = signature(ret, args)
checked = set()
for path in (ROOT/'.lake/build/ir').rglob('*.c'):
    for ret, name, args in pattern.findall(path.read_text(encoding='utf-8')):
        if name == 'lean_blinky_run':  # Demo export, implemented by Lean itself.
            continue
        if name not in definitions:
            raise AssertionError('No C implementation: ' + name)
        assert signature(ret, args) == definitions[name], (path, name, args, definitions[name])
        checked.add(name)
assert checked == definitions.keys(), 'Unverified C exports: ' + str(definitions.keys() - checked)
print(f'PASS: {len(checked)} native bridge signatures match Lean-generated declarations')
