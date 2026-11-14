import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent

MUTANTS = [
    ("rtl/rv_core_pipe.sv", "WB-to-ID bypass removed",
     "assign id_rs1v = (wb_rf_wen && w_rd == id_rs1) ? w_result : id_rf1;", "assign id_rs1v = id_rf1;"),
    ("rtl/rv_core_pipe.sv", "older MEM/WB producer preferred over EX/MEM",
     "(m_valid && m_rf_we && m_rd == e_rs1) ? FW_MEM :\n                 (w_valid && w_rf_we && w_rd == e_rs1) ? FW_WB : FW_REG;",
     "(w_valid && w_rf_we && w_rd == e_rs1) ? FW_WB :\n                 (m_valid && m_rf_we && m_rd == e_rs1) ? FW_MEM : FW_REG;"),
    ("rtl/rv_core_pipe.sv", "hazard check ignores rd = x0",
     "assign hit1_e = id_uses_rs1 && id_rs1 != 5'd0 &&", "assign hit1_e = id_uses_rs1 &&"),
    ("rtl/rv_core_pipe.sv", "taken branch does not flush ID",
     "assign kill_d = kill_e || ex_redirect;", "assign kill_d = kill_e;"),
    ("rtl/rv_core_pipe.sv", "load-use stall removed",
     "if (e_load && (hit1_e || hit2_e)) stall_reason = ST_LOAD_USE;", "if (1'b0) stall_reason = ST_LOAD_USE;"),
    ("rtl/rv_core_pipe.sv", "older MEM fault does not squash younger EX",
     "assign kill_e = kill_m || (m_valid && mem_cause != C_NONE);", "assign kill_e = kill_m;"),
    ("rtl/rv_core_pipe.sv", "store data not forwarded",
     "m_sdata  <= ex_rs2;", "m_sdata  <= e_rs2v;"),
    ("rtl/rv_alu.sv", "SRA behaves as SRL",
     "ALU_SRA:  y = $unsigned($signed(a) >>> b[4:0]);", "ALU_SRA:  y = a >> b[4:0];"),
    ("rtl/rv_mem.sv", "LB not sign-extended",
     "2'd0:    d_rdata = d_unsigned ? {24'b0, rsh[7:0]}  : {{24{rsh[7]}}, rsh[7:0]};",
     "2'd0:    d_rdata = {24'b0, rsh[7:0]};"),
    ("rtl/rv_core_sc.sv", "JALR does not clear bit 0",
     "assign target     = is_jalr ? ((rs1v + imm) & ~32'h1) : (pc_q + imm);",
     "assign target     = is_jalr ? (rs1v + imm) : (pc_q + imm);"),
    ("rtl/rv_core_sc.sv", "not-taken branch checks its target",
     "assign target_mis = take & target[1];", "assign target_mis = (take | is_branch) & target[1];"),
    ("rtl/rv_decode.sv", "SUB decoded as ADD",
     "alu_op = ALU_SUB;", "alu_op = ALU_ADD;"),
    ("rtl/rv_decode.sv", "FENCE.I accepted",
     "bad = funct3 != 3'b000;\n        end\n        OP_SYSTEM", "bad = 1'b0;\n        end\n        OP_SYSTEM"),
]


def main():
    killed = 0
    total = 0
    lines = []
    for rel, desc, old, new in MUTANTS:
        path = ROOT / rel
        orig = path.read_text()
        if old not in orig:
            raise SystemExit(f"mutant '{desc}' no longer matches {rel}")
        total += 1
        try:
            path.write_text(orig.replace(old, new, 1))
            p = subprocess.run([sys.executable, str(ROOT / "tools" / "run_tests.py"), "--no-selftest",
                                "--log", "build/mutation_run.log"], cwd=ROOT, capture_output=True, text=True)
        finally:
            path.write_text(orig)
        first = next((l[4:] for l in p.stdout.splitlines() if l.startswith("  - ")), "")
        status = "killed" if p.returncode != 0 else "SURVIVED"
        killed += p.returncode != 0
        lines.append(f"{status:<9} {desc:<46} {first[:110]}")
        print(lines[-1], flush=True)
    summary = f"{killed}/{total} mutants killed by the regression"
    print(summary)
    (ROOT / "build" / "mutation.log").write_text("\n".join(lines + [summary]) + "\n")
    sys.exit(0 if killed == total else 1)


if __name__ == "__main__":
    main()
