# Headless VM execution

The default transport matches the existing machine setup:

| Setting | Default |
| --- | --- |
| SSH identity/host | `linuxvm` |
| macOS shared directory | `/Volumes/Ext/VM_SharedFolder` |
| VM shared directory, relative to SSH home | `macshared` |
| VM model | `$HOME/FVP_Corstone_SSE-300/models/Linux64_armv8l_GCC-9.3/FVP_Corstone_SSE-300_Ethos-U55` |

Use `FVP_SSH_HOST`, `FVP_SHARED_DIR`, and `FVP_VM_SHARED_DIR` in the VS Code environment to override transport paths. The VM's `FVP_MODEL` environment variable can override the model executable. The program is launched from a unique task-owned directory in the shared folder, with a generated `launch.sh` executed by Bash inside the VM. Original shared-folder scripts and ELF files are not modified.

`board/Corstone300/fvp.cfg` sets the core clock to 32 MHz to match the BSP's `SystemCoreClock`. It enables semihosting, the FPU and MVE. It disables visualization and automatic telnet terminal startup for all four terminals. Listening port messages are normal; no UI is launched and no serial connection is used by the test.

Each model run is limited to 30 seconds, with a further five-second forced-termination bound. Core dumps are disabled. Its temporary shared-folder copy is removed after completion; the original local ELF and JSON evidence remain. A failed test, load warning, nonzero model status, or timeout must not be treated as a pass.

The current model is older than the native GDBServer plugin. The CMSIS **Arm-FVP** adapter generates both Run and GDB entries, but the shim explicitly rejects the debug/plugin arguments on this installation. A future upgrade can add native GDBServer support in the VM; it is not necessary for the verified headless run flow and was not installed by this task.

CMSIS Developer Assistant currently describes `load_and_run` as though every Run task were a persistent GDB server. A self-terminating FVP test can therefore be reported as failed if it exits quickly, even with status zero, or initially reported as started before its test finishes. The authoritative validation here is the completed run's return code, all expected PASS markers, absence of fault/load failures, and SHA-256 match against the current ELF. `scripts/verify-evidence.py` checks those conditions.

Memory comes from the installed BSP's secure ITCM and DTCM aliases: 512 KiB at `0x10000000` for code and four contiguous 128 KiB DTCM banks at `0x30000000` for data. The linker keeps zero-initialized RAM in a RAM-addressed ELF segment and heap/stack reservations out of load segments. This prevents an FVP loader from trying to zero those reservations at a flash load address.

The optional Console build uses the secure SRAM alias at `0x11000000` (1 MiB) for its larger standard-library code closure, and keeps reset/interrupt vectors at `0x10000000`. Its data/RTX/heap/stack budgets remain in DTCM. This layout is separately tested with both compilers.
