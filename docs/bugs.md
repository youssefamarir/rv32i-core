# Bugs found and fixed

## 1. The first instruction never appeared in the retirement log

**Symptom.** The first smoke run printed five `R` records. The program has six non-stop instructions.

**Cause.** The testbench released reset on a falling edge and sampled retirements on falling edges. On the release edge the monitor still saw reset high, so instruction 0 executed and committed on the next rising edge without being logged.

**Fix.** Defined the interface so a record is valid during the cycle and sampled on the rising edge that commits it. The testbench now checks the first fetch address and logs all six records.

## 2. A run with an all-X signature reported PASS

**Symptom.** The first `pipe_nofwd` smoke run printed `SIG value=xxxxxxxx` followed by `PASS`.

**Cause.** Two problems together. The checks used `!=`, which evaluates to X when either side is X, so `if` treated the mismatch as false. The X came from the forwarding-select block: with `FORWARD = 0` its `always @(*)` body only assigned constants, so it had nothing to be sensitive to and never ran (Icarus warned: "@* found no sensitivities"). `fwd_a`/`fwd_b` stayed X and corrupted every EX operand.

**Fix.** All testbench comparisons use `!==` / `===`. The forwarding selects became continuous assignments.

## 3. The C demo stored X on its fourth instruction

**Symptom.** `demo` failed in all three configurations at record 3, `sw s1,116(sp)`: RTL store data `xxxxxxxx`, reference `00000000`.

**Cause.** GCC's prologue for `main` saves callee-saved registers that nothing had written. The RTL register file intentionally powers up as X; the reference model starts at zero.

**Fix.** `firmware/start.S` clears `x1`-`x31` before setting `sp`, as a normal crt0 does. The register file stays X at power-up so any program that reads an uninitialized register still fails the comparison.

## 4. Trace dump could not be decoded

**Symptom.** `trace_decode.py` crashed on `xxxx` fields in the first samples.

**Cause.** Empty pipeline stages still carried uninitialized PCs and forwarding selects.

**Fix.** The trace sample reports 0 for the PC and forward select of an empty stage. The decoder also reads only the slots that have been written.

## 5. A pipeline bug that the regression did not catch

**How it was found.** `tools/mutation_check.py` injects deliberate RTL bugs and requires the regression to fail. Removing "an older fault in MEM kills younger EX/ID/IF" survived.

**Why.** A younger store was still blocked one cycle later by the WB-stage gate, so no wrong store or register write reached architectural state. The younger jump in EX did redirect the PC, which a retirement comparison cannot see.

**Fix.** `p_fault_jump` and `p_fault_misaligned_branch` now require zero redirects in both pipeline modes. All 13 mutants are caught.
