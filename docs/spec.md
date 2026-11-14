# RV32I core specification

## Contract

| Decision | Choice |
| --- | --- |
| ISA | RV32I base, little-endian, 32 x 32-bit registers, fixed 32-bit instructions. No CSRs, interrupts, or extensions. |
| Reset | Synchronous, active-high. PC = `0x00000000`. While reset is asserted the core retires nothing, writes no register, and commits no store. |
| Instruction ROM | 4 KiB at `0x00000000`, 1,024 words, combinational read, loaded from a 1,024-line hex file. Data loads from ROM are allowed (C constants). |
| Data RAM | 4 KiB at `0x00010000`, combinational read, rising-edge write with four byte enables. |
| Signature register | 32-bit word at `0x80000000`. Word stores set it; word loads read it back. |
| Address conventions | Byte addresses on all CPU ports. ROM/RAM word index = `(addr - BASE) >> 2`. RAM contents are undefined to programs until written; the simulator zero-fills them only for determinism. Registers other than `x0` start as `X` in RTL, so a program that reads an uninitialized register fails the reference comparison. |
| Execution environment | Bare-metal. Any trap stops the core and reports a stop record (cause, PC). No trap handler. |
| Instruction alignment | 4 bytes. A taken branch or jump to a target with `target[1] = 1` stops with `INST_MISALIGNED` at the branch/jump PC. JALR clears bit 0 before the check. A not-taken branch never checks its target. |
| Data alignment | Misaligned halfword and word accesses trap (`LOAD_MISALIGNED` / `STORE_MISALIGNED`). Alignment is checked before mapping. |
| Unmapped accesses | Loads outside ROM, RAM, and the signature word trap with `LOAD_ACCESS`. Stores outside RAM and the signature word, including any store to ROM, trap with `STORE_ACCESS`. Byte and halfword accesses to the signature word trap as access faults. Fetch outside ROM traps with `FETCH_ACCESS` at the fetch PC. |
| Faulting instructions | Produce no register write, no store, and no retirement record. |
| FENCE | Executes as a no-op. The memory system is a single in-order port with no caches or buffers, so every access is already globally ordered. `FENCE.I` (Zifencei) is illegal. |

## Stop causes

| Code | Name | Reported PC |
| ---: | --- | --- |
| 1 | `EBREAK` | EBREAK instruction |
| 2 | `ECALL` | ECALL instruction |
| 3 | `ILLEGAL` | Illegal instruction |
| 4 | `INST_MISALIGNED` | Taken branch / jump |
| 5 | `FETCH_ACCESS` | Unmapped fetch address |
| 6 | `LOAD_MISALIGNED` | Load |
| 7 | `LOAD_ACCESS` | Load |
| 8 | `STORE_MISALIGNED` | Store |
| 9 | `STORE_ACCESS` | Store |

Priority inside one instruction: fetch fault, illegal, ECALL, EBREAK, misaligned target, load/store misaligned, load/store access. Across instructions, the oldest stop wins and younger instructions leave no architectural effect.

## Retirement interface

One record per completed instruction, valid for one cycle and sampled on the rising edge that commits it. Both cores use the same format.

```text
R <seq> <pc> <inst> <rd> <rd_data> <st_addr> <st_be> <st_data>
S <cause> <pc>
```

* `seq` counts retired instructions from 0.
* `rd`/`rd_data` are `-- --------` when there is no architectural register write (including `rd = x0`).
* Stores are normalized to the aligned word address, a 4-bit lane mask, and data placed in its lanes with other lanes zero. `-------- - --------` means no store.
* `S` is emitted once, for the instruction that stopped the core.

## Instruction matrix

Implemented = in both cores. Tested = a directed test checks the instruction's result in the program itself and the full event stream is compared against the reference model in all three core configurations.

| Group | Instructions | Implemented | Independently tested | Directed tests |
| --- | --- | :---: | :---: | --- |
| Upper immediate | LUI, AUIPC | yes | yes | `alu`, `reset_x0` |
| Jumps | JAL, JALR | yes | yes | `branches`, `f_jal_misaligned`, `f_jalr_misaligned`, `p_jalr_fwd` |
| Branches | BEQ, BNE, BLT, BGE, BLTU, BGEU | yes | yes | `branches`, `f_branch_misaligned`, `p_branch_flush` |
| Loads | LB, LH, LW, LBU, LHU | yes | yes | `mem_lanes`, `f_load_*`, `p_loaduse` |
| Stores | SB, SH, SW | yes | yes | `mem_lanes`, `f_store_*`, `p_store_fwd` |
| Integer immediate | ADDI, SLTI, SLTIU, XORI, ORI, ANDI, SLLI, SRLI, SRAI | yes | yes | `alu` |
| Register-register | ADD, SUB, SLL, SLT, SLTU, XOR, SRL, SRA, OR, AND | yes | yes | `alu` |
| System / ordering | FENCE, ECALL, EBREAK | yes | yes | `fence`, `f_ecall`, `smoke` |

All 37 RV32I instructions plus FENCE, ECALL and EBREAK are implemented. Seeded random programs add coverage of every group except system instructions.

## Configurations

| Name | Core | Forwarding |
| --- | --- | --- |
| `sc` | Single-cycle | n/a |
| `pipe_nofwd` | Five-stage | Off: interlock until the producer reaches WB (WB-to-ID bypass) |
| `pipe_fwd` | Five-stage | EX/MEM and MEM/WB forwarding, one-bubble load-use stall |
