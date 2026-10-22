# Lean 4 on Cortex-M55 / CMSIS-RTX

Cross-compile Lean applications with the **stock Lean 4.35.0 compiler and Lake**, then run them on the headless Corstone-300 FVP. Both CMSIS compiler selections are supported and tested:

| CMSIS target | C/C++ toolchain | C/C++ libraries |
| --- | --- | --- |
| `Corstone300-GCC` | GCC 14.3.1 | newlib / libstdc++ |
| `Corstone300-CLANG` | Arm Toolchain for Embedded (ATfE) 23.1.0 | picolibc / libc++ |

The Lean compiler is not rebuilt. The runtime comes from the exact matching upstream commit in [upstream.json](upstream.json). Threading stays enabled: the upstream task scheduler runs on real RTX threads, with per-thread runtime state, blocking synchronization, and thread finalization.

The example imports only `Init.Prelude`, `Init.Coe`, and `Init.Notation`, plus the application and a local Lake dependency containing the hardware proof. There is no blanket `import Init`, no full Lean standard-library archive, and no fake `initialize_Init` function. Real module initializers run; unused C functions are removed at link time.

## Build and run in VS Code

The workspace manifest selects the installed CMSIS-Toolbox, CMake, Ninja, GCC, and ATfE versions. Python 3, Git, and the existing Lean/Lake installation must also be on PATH.

1. Fetch the pinned runtime sources once:

   ```sh
   python3 scripts/fetch-sources.py
   ```

   This makes a shallow clone under `.reference/lean4`. It installs no Nix and builds no host compiler.

2. Open [LeanEmbedded.csolution.yml](LeanEmbedded.csolution.yml) in the CMSIS Solution extension. Activate the environment in `vcpkg-configuration.json` if prompted. The required packs are CMSIS 6.3.0, CMSIS-RTX 5.9.1, and the MPS3 SSE-300 BSP 1.4.0.
3. Select the `minimal` target set on `Corstone300-CLANG` or `Corstone300-GCC`, then **Build**. CMSIS-Toolbox 2.15 orchestrates the native CMake project; CMake invokes Lake, cross-compiles its generated C and the runtime, and links the firmware.
4. Select **Run** / **Load + Run**. The Arm-FVP adapter invokes `scripts/fvp-model.py`, which copies the ELF into the shared folder and executes the model **inside the VM** over the `linuxvm` SSH identity.
5. Repeat for the other compiler. Validate the two current images with:

   ```sh
   python3 scripts/verify-evidence.py
   ```

Seven PASS lines cover arithmetic, tasks, TLS/exceptions, mutexes, promises/heap/once guards, references/time, and the proved SysTick register example. Every run records its ELF SHA-256, return code, console output, and FVP configuration hash in `.build/evidence/`.

The installed VM FVP has no GDBServer plugin. **Run is verified; Load & Debug is not supported by that model.** The generated GDB launch entry reports that limitation explicitly. No pyOCD, board connection, simulator UI, or telnet window is needed. See [FVP setup](docs/fvp.md) for paths and overrides.

## Optional standard Lean console example

Select the `console` target set (`Corstone300-CLANG@console` or `Corstone300-GCC@console`) and use Build/Run. This selects the `Console` build type and adds `examples/console/Console.lean`. It runs ordinary `Task.spawn`/`Task.map`, `IO.sleep`, and `IO.println` using the same stock Lean compiler and RTX runtime.

The larger `Init.System.IO` dependency closure is opt-in. Its code uses the FVP's 1 MiB secure SRAM code region, with boot vectors in ITCM. The minimal default continues to use five Lean modules and 512 KiB ITCM for code. After running both profiles with both compilers, verify all four images with:

```sh
python3 scripts/verify-evidence.py --console
```

Standard-module generated C is cached under `.build/lean-c/<commit>` and reused across compilers. No host library archive is linked into the target.

## Develop a Lean application

Edit `examples/smoke/Smoke.lean` and build through CMSIS. Lean elaboration, proof checking, C generation, and native compilation are all part of the build. Lake warnings are errors, including uses of `sorry`.

Use the module system and explicit imports to control the firmware library footprint:

```lean
module
prelude
public import Init.Notation

@[expose] public section

@[export my_embedded_function]
def compute (n : Nat) : Nat := (n + 42) * (n + 1)
```

The host compiler still uses its installed libraries to elaborate the program. The firmware contains the runtime and the selected modules' runtime code. Proofs are erased.

Add ordinary Lake dependencies in `lakefile.toml`. The included `hardware_contracts` dependency demonstrates a separate package without network access. After changing remote dependency declarations, resolve them with normal Lake tooling; then build the CMSIS solution. The C-generation script obtains package artifacts through Lake's `:c` facet and discovers their import closure. Unsupported platform imports produce errors or unresolved symbols, rather than pretend to work.

C-facing exported functions use Lean's generated ABI. The generated `lean_app_init.h` selects the correct package-qualified runtime initializer; do not guess initializer names. The C harness shows initialization in a running RTX thread, module initialization, `lean_io_mark_end_initialization()`, and explicit task-manager lifetime.

## What is implemented

See [runtime design and capability limits](docs/runtime.md), [the proved SysTick example](docs/proof-example.md), and [validation](docs/validation.md). This is a core runtime port for a single Cortex-M55, not a POSIX environment or an entire Lean compiler running on the MCU.

The native CMake project is deliberately used as a first-class `cmake:` entry in a standard csolution. Board, compiler, pack, build, and Run selection remain in the CMSIS UI. Startup and RTX sources are selected by CMake from the pinned packs; this project does not present them as a separate RTE-managed `.cproject.yml` component graph.

## License and source provenance

Project code is Apache-2.0. Upstream Lean and CMSIS source notices remain intact. Compiler-provided libraries keep their respective licenses and runtime exceptions. `.reference`, `.lake`, generated runtime copies, and firmware outputs are ignored by Git.

The [lean-esp32 project](https://codeberg.org/kuruczgy/lean-esp32) was the reference for the original use case. This implementation uses matching upstream Lean sources and keeps its task machinery, rather than adopting that project's slimmed-down runtime.
