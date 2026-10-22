# A proved SysTick reload contract

The small separate Lake package in `examples/hardware-contracts` defines `SysTickConfig period`. A value carries:

1. A reload value below 16,777,216 (`Fin 16777216`).
2. A proof that the reload is positive.
3. A proof that `period = reload + 1`.

`checkedSysTick` rejects periods zero and one, checks the remaining upper bound, and constructs the value together with its proofs. The `noReservedBits`, `nonzeroReload`, and `exactPeriod` theorems project these guarantees. `rejectsZero` and `rejectsOne` are proved by reduction. There are no added axioms or `sorry`s, and Lake treats warnings as errors.

This corresponds to actual hardware constraints. The Armv8-M Architecture Reference Manual, **DDI0553 B.z p.290**, specifies that a zero reload disables counting on the next wrap. **p.1859** specifies the 24-bit RELOAD field, reserved upper eight bits, privileged access, and word-only accesses. The Cortex-M55 TRM, **101051 r1p1 p.240**, lists SYST_RVR at `0xE000E014`. The architecture rules cited apply from Armv8.0-M onward, including this Armv8.1-M target.

At the exported C boundary, `sysTickReload` returns zero to signal rejection. Accepted values use the proof-requiring `UInt32.ofNatLT`, so the conversion does not silently wrap the proved Nat value. The result is used by a C MMIO shim that only writes when the result is nonzero.

The FVP test checks these seven periods:

| Requested period | Result |
| --- | --- |
| 0 | rejected |
| 1 | rejected; zero reload would stop the counter |
| 2 | reload 1 |
| 1,000 | reload 999 |
| 16,777,216 | reload 16,777,215 |
| 16,777,217 | rejected |
| 4,294,967,295 | rejected |

It reads the actual SysTick LOAD register after accepted writes and verifies that rejected values leave it unchanged. RTX owns SysTick, so the test temporarily stops the counter under kernel/interrupt locks after worker tests complete, then restores its configuration. Production code should give such a driver ownership of its timer rather than reconfigure the RTOS tick while the kernel is active.

The proof covers the Lean contract and its value conversion. The Lean kernel, compiler, runtime, C ABI/MMIO shim, CMSIS device definitions, and FVP hardware model remain trusted. The seven runtime cases validate the integration; they are not a replacement for the universal proof.
