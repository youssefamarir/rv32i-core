# Test matrix

Every program below runs on all three configurations (`sc`, `pipe_nofwd`, `pipe_fwd`). Each run is self-checking in the testbench (stop cause, stop PC, signature, no writes during reset or on the stopping instruction, timeout) and its full retirement stream is compared record by record with the Python reference model. Expected values live in `tools/tests.json`.

| Requirement | Tests | Evidence of a pass |
| --- | --- | --- |
| Smoke | `smoke` | Signature `0x0000000c`, six retirements, EBREAK at `0x18` |
| Reset and x0 | `reset_x0`, testbench checks | First fetch after reset at `0x0`; no retirement, register write, or store while reset is high; writes to `x0` by ALU, LUI, load and JAL read back as zero |
| Arithmetic and comparison | `alu` | `0xFFFFFFFF + 1 = 0`; `slt -1,1 = 1`; `sltu 0xFFFFFFFF,1 = 0`; shifts by 0, 1, 31 and 33 (masked to 1); SRA vs SRL of `0x80000001`; all R and I ops, negative immediates, LUI, AUIPC with positive and negative offsets |
| Byte lanes and extension | `mem_lanes`, `p_store_fwd` | RAM `0x807FFF01`: `LB+1 = 0xFFFFFFFF`, `LBU+1 = 0xFF`, `LH+2 = 0xFFFF807F`, `LHU+2 = 0x807F`; `SB 0xAA @+2` gives `0x80AAFF01`; SH at offsets 0 and 2; negative offsets; loads from ROM constants; signature read-back |
| Branches and jumps | `branches`, `p_jalr_fwd` | All six branches taken and not taken including signed/unsigned edge cases; backward loops on BNE, BLTU, BLT, BGE, BEQ, BGEU; JAL/JALR write `PC+4`; JALR clears bit 0, uses negative offsets, and works with `rd == rs1`; not-taken branches to misaligned targets do not fault |
| Stops and faults | `f_*` (22 programs) | Each cause and stop PC from `docs/spec.md`: illegal (zero word, CSR, bad `funct7`, FENCE.I, bad load width, bad shift), ECALL, fetch outside ROM and past its end, load/store outside the map, ROM store, byte access to the signature, misaligned LW/LH/SW/SH, misaligned JAL/JALR/branch targets. The signature must stay unwritten and the stopping instruction must not write |
| FENCE | `fence` | FENCE variants including FENCE.TSO execute as no-ops; a load after a fenced store sees the store |
| Pipeline hazards | `p_fwd`, `p_loaduse`, `p_branch_flush`, `p_fault_store`, `p_fault_jump`, `p_fault_misaligned_branch`, `p_x0`, `p_store_fwd`, `p_jalr_fwd` | `x6 = 84` with zero stalls; `x6 = 42` with exactly one load-use stall in `pipe_fwd`; the taken branch over `sw` and an illegal word gives one redirect and one signature write; older faulting load beats a younger store or jump (no store, no redirect); producers writing `x0` cause zero stalls in both modes |
| Retirement comparison | all | Records compared in order: PC, instruction, destination and value, normalized store address/lanes/data, stop cause and PC. The streams from all three configurations must also be identical |
| Random programs | `rand_1` ... `rand_10` | Deterministic seeds; ALU, shifts, LUI/AUIPC, all load/store widths at negative and positive offsets into an initialized window, forward branches, bounded backward loops, JAL, JALR with bit 0 set, `x0` and back-to-back dependencies |
| C workload | `demo` | Freestanding C (fill with xorshift, insertion sort, checksum) compiled at `-O2`; expected value computed independently by `tools/demo_expected.py`; ISA and memory-map check on the linked ELF |
| Trace buffer | `sim/trace_tb.sv`, trace captures in `run_tests.py` | Capture, wrap, enable, masked trigger, exact trigger index, post-trigger window, freeze, rearm, reset; on the pipeline, a stall trigger and a redirect trigger each freeze after exactly the configured window |
| Checker self-test | `run_tests.py` (built in) | A wrong expected signature and a corrupted reference record each make the regression exit with code 1 |
| Mutation check | `tools/mutation_check.py` | 13 deliberate RTL bugs, each caught by the regression |
