import json
import re
import subprocess
import sys
from pathlib import Path

import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt
from matplotlib.patches import Rectangle

ROOT = Path(__file__).resolve().parent.parent
BUILD = ROOT / "build"
EVID = ROOT / "evidence"
sys.path.insert(0, str(ROOT / "tools"))

import run_tests

CLK_NS = 10
INK = "#1f2933"
GRID = "#d9dee5"
WAVE = "#1d5fa8"
ACCENT = "#c2410c"
FAINT = "#7b8794"


def parse_vcd(path):
    ids, changes, scope = {}, {}, []
    t = 0
    scale = 1.0
    with open(path) as fh:
        header = True
        for line in fh:
            parts = line.split()
            if not parts:
                continue
            if header:
                if "ps" in parts and "$timescale" in parts:
                    scale = 0.001
                if parts[0] == "$timescale":
                    nxt = next(fh).split()
                    scale = {"ps": 0.001, "ns": 1.0}.get(re.sub(r"[0-9]", "", nxt[0]), 1.0) * float(re.sub(r"[a-z]", "", nxt[0]) or 1)
                if parts[0] == "$scope":
                    scope.append(parts[2])
                elif parts[0] == "$upscope":
                    scope.pop()
                elif parts[0] == "$var":
                    width, code, name = int(parts[2]), parts[3], parts[4]
                    ids.setdefault(code, []).append((".".join(scope + [name]), width))
                elif parts[0] == "$enddefinitions":
                    header = False
                continue
            tok = parts[0]
            if tok[0] == "#":
                t = int(tok[1:]) * scale
            elif tok[0] in "bB":
                changes.setdefault(parts[1], []).append((t, tok[1:]))
            elif tok[0] in "01xzXZ" and len(tok) > 1:
                changes.setdefault(tok[1:], []).append((t, tok[0]))
    sigs = {}
    for code, names in ids.items():
        for name, width in names:
            sigs[name] = (width, changes.get(code, []))
    return sigs


def value_at(sig, t):
    width, ch = sig
    v = "x"
    for tc, val in ch:
        if tc > t:
            break
        v = val
    return width, v


def fmt(width, v):
    if any(c in "xXzZ" for c in v):
        return "x"
    n = int(v, 2)
    if width == 1:
        return str(n)
    return f"{n:0{(width + 3) // 4}x}" if width > 8 else f"{n:x}"


def segments(sig, t0, t1):
    width, ch = sig
    pts = [t0] + [tc for tc, _ in ch if t0 < tc < t1] + [t1]
    out = []
    for a, b in zip(pts, pts[1:]):
        out.append((a, b, fmt(*value_at(sig, a))))
    merged = []
    for seg in out:
        if merged and merged[-1][2] == seg[2]:
            merged[-1] = (merged[-1][0], seg[1], seg[2])
        else:
            merged.append(seg)
    return merged


def draw_wave(sigs, rows, t0, t1, title, out, cursor=None, notes=(), cycle0=0, subtitle=""):
    n = len(rows)
    fig_w = 13
    fig_h = 1.1 + 0.42 * n
    fig, ax = plt.subplots(figsize=(fig_w, fig_h), dpi=150)
    ax.set_xlim(t0 - (t1 - t0) * 0.2, t1)
    ax.set_ylim(-0.8, n + 0.2)
    ax.axis("off")
    lx = t0 - (t1 - t0) * 0.195
    k = cycle0 + -(-(t0 - cycle0) // CLK_NS) * CLK_NS
    while k <= t1:
        ax.plot([k, k], [-0.3, n], color=GRID, lw=0.6, zorder=0)
        if k + CLK_NS <= t1:
            ax.text(k + CLK_NS / 2, -0.55, str(int((k - cycle0) // CLK_NS)), ha="center", va="center",
                    fontsize=7, color=FAINT, family="DejaVu Sans Mono")
        k += CLK_NS
    ax.text(lx, -0.55, "cycle", fontsize=7, color=FAINT, va="center", family="DejaVu Sans Mono")
    for i, (label, path) in enumerate(rows):
        y = n - 1 - i
        ax.text(lx, y + 0.35, label, fontsize=8.5, va="center", color=INK, family="DejaVu Sans Mono")
        sig = sigs[path]
        width = sig[0]
        segs = segments(sig, t0, t1)
        if width == 1:
            prev = None
            for a, b, v in segs:
                lvl = 0.65 if v == "1" else 0.05 if v == "0" else 0.35
                col = WAVE if v in "01" else ACCENT
                ax.plot([a, b], [y + lvl, y + lvl], color=col, lw=1.3)
                if prev is not None and prev != lvl:
                    ax.plot([a, a], [y + prev, y + lvl], color=WAVE, lw=1.3)
                prev = lvl
        else:
            for a, b, v in segs:
                e = min(1.2, (b - a) / 4)
                xs = [a, a + e, b - e, b, b - e, a + e, a]
                ys = [y + 0.35, y + 0.65, y + 0.65, y + 0.35, y + 0.05, y + 0.05, y + 0.35]
                ax.fill(xs, ys, color="#eef4fb" if v != "x" else "#fbeee6", zorder=1)
                ax.plot(xs, ys, color=WAVE if v != "x" else ACCENT, lw=0.9, zorder=2)
                if b - a >= 6:
                    ax.text((a + b) / 2, y + 0.35, v, ha="center", va="center", fontsize=7.2,
                            color=INK, family="DejaVu Sans Mono", zorder=3)
    if cursor is not None:
        ax.plot([cursor, cursor], [-0.3, n + 0.05], color=ACCENT, lw=1.4, ls="--", zorder=4)
    for t, y_row, text in notes:
        y = n - 1 - y_row
        ax.plot([t, t], [y + 0.68, y + 0.76], color=ACCENT, lw=1.0, zorder=5)
        ax.text(t, y + 0.86, text, ha="center", va="center", fontsize=7, color=ACCENT, zorder=6,
                bbox=dict(boxstyle="round,pad=0.12", fc="white", ec="none"))
    fig.suptitle(title, x=0.02, ha="left", fontsize=11, color=INK, fontweight="bold")
    if subtitle:
        fig.text(0.02, 0.985 - 0.32 / fig_h, subtitle, fontsize=8, color=FAINT, ha="left", va="top")
    fig.tight_layout(rect=(0, 0, 1, 1 - 0.45 / fig_h))
    fig.savefig(out)
    plt.close(fig)


def text_image(lines, out, title, highlight=(), width=13):
    h = 0.9 + 0.17 * len(lines)
    fig, ax = plt.subplots(figsize=(width, h), dpi=150)
    ax.axis("off")
    ax.set_xlim(0, 1)
    ax.set_ylim(0, len(lines) + 1)
    for i, line in enumerate(lines):
        y = len(lines) - i
        hl = any(k in line for k in highlight)
        if hl:
            ax.add_patch(Rectangle((0, y - 0.45), 1, 0.9, color="#fff1e6", zorder=0))
        bold = line.startswith(("PS>", "RESULT", "programs=")) or hl
        ax.text(0.005, y, line, family="DejaVu Sans Mono", fontsize=7.6, va="center",
                color=ACCENT if line.startswith("RESULT") else INK, fontweight="bold" if bold else "normal")
    fig.suptitle(title, x=0.01, ha="left", fontsize=11, color=INK, fontweight="bold")
    fig.tight_layout(rect=(0, 0, 1, 1 - 0.3 / h))
    fig.savefig(out)
    plt.close(fig)


def simulate(vvp, cfg, test, vcd, extra=()):
    hexf = BUILD / "tests" / test / f"{test}.hex"
    manifest = {t["name"]: t for t in json.loads((ROOT / "tools" / "tests.json").read_text())["tests"]}
    t = manifest[test]
    cmd = [vvp, "-n", f"build/core_{cfg}.vvp", f"+hex={run_tests.rel(hexf)}", f"+vcd={run_tests.rel(vcd)}",
           f"+cause={run_tests.refmodel.CAUSES[t['cause']]}", "+timeout=2000"]
    cmd.append(f"+sig={t['sig']}" if "sig" in t else "+nosig")
    p = subprocess.run(cmd + list(extra), cwd=ROOT, capture_output=True, text=True)
    if "PASS" not in p.stdout:
        raise SystemExit(f"simulation of {test} on {cfg} failed:\n{p.stdout}{p.stderr}")
    return parse_vcd(vcd)


def first_time(sig, pred, after=0):
    for t, v in sig[1]:
        if t >= after and pred(v):
            return t
    return None


def main():
    if not (BUILD / "results.json").exists():
        raise SystemExit("run python tools/run_tests.py first")
    _, vvp = run_tests.find_sim()
    EVID.mkdir(exist_ok=True)
    wdir = BUILD / "evidence"
    wdir.mkdir(parents=True, exist_ok=True)

    sigs = simulate(vvp, "sc", "smoke", wdir / "smoke_sc.vcd")
    t_rst = first_time(sigs["core_tb.rst"], lambda v: v == "0")
    t_st = first_time(sigs["core_tb.ret_st_valid"], lambda v: v == "1")
    t_stop = first_time(sigs["core_tb.stop_valid"], lambda v: v == "1")
    rows = [("clk", "core_tb.clk"), ("rst", "core_tb.rst"), ("fetch_pc", "core_tb.fetch_pc"),
            ("fetch_inst", "core_tb.fetch_inst"), ("ret_valid", "core_tb.ret_valid"),
            ("ret_pc", "core_tb.ret_pc"), ("ret_rd", "core_tb.ret_rd"), ("ret_rd_we", "core_tb.ret_rd_we"),
            ("ret_rd_wdata", "core_tb.ret_rd_wdata"), ("st_commit", "core_tb.st_commit"),
            ("st_addr", "core_tb.ret_st_addr"), ("st_data", "core_tb.ret_st_data"),
            ("sig_value", "core_tb.sig_value"), ("stop_valid", "core_tb.stop_valid"),
            ("stop_cause", "core_tb.stop_cause")]
    draw_wave(sigs, rows, t_rst - 25, t_stop + 15, "smoke.S on the single-cycle core", EVID / "02-smoke-wave.png",
              cursor=t_st + CLK_NS, cycle0=t_rst - 5,
              notes=[(t_st + CLK_NS / 2, 10, "sw x3 -> 0x80000000 = 0x0000000c"),
                     (t_stop + CLK_NS / 2, 13, "EBREAK stop (cause 1, pc 0x18)")],
              subtitle="x1=7, x2=5, x3=12, one full-word store to the signature, then EBREAK. "
                       "Records are sampled on the rising edge that commits them (cursor: signature update).")

    sigs = simulate(vvp, "pipe_fwd", "p_loaduse", wdir / "loaduse_fwd.vcd")
    core = "core_tb.dut.g_pipe.u_core."
    t_rst = first_time(sigs["core_tb.rst"], lambda v: v == "0")
    t_hold = first_time(sigs[core + "stall_eff"], lambda v: v == "1")
    t_fwd = first_time(sigs[core + "fwd_a"], lambda v: v == "10", after=t_hold)
    t_ret = first_time(sigs["core_tb.ret_pc"], lambda v: int(v, 2) == 0x14 if "x" not in v else False, after=t_hold)
    rows = [("clk", "core_tb.clk"), ("IF pc", core + "pc_f"), ("ID pc", core + "d_pc"), ("ID valid", core + "d_valid"),
            ("EX pc", core + "e_pc"), ("EX valid", core + "e_valid"), ("EX load", core + "e_load"),
            ("stall", core + "stall_eff"), ("fwd_a sel", core + "fwd_a"), ("MEM pc", core + "m_pc"),
            ("MEM valid", core + "m_valid"), ("WB pc", core + "w_pc"), ("WB result", core + "w_result"), ("ret_valid", "core_tb.ret_valid"),
            ("ret_pc", "core_tb.ret_pc"), ("ret_rd_wdata", "core_tb.ret_rd_wdata")]
    a = t_hold - 3 * CLK_NS
    draw_wave(sigs, rows, a, t_ret + 2 * CLK_NS, "Load-use: lw x5,0(x10) then addi x6,x5,1 (pipe_fwd)",
              EVID / "03-load-use-wave.png", cycle0=t_rst - 5,
              notes=[(t_hold + CLK_NS / 2, 7, "hold IF/ID"), (t_hold + 1.5 * CLK_NS, 5, "EX bubble"),
                     (t_fwd + CLK_NS / 2, 8, "forward MEM/WB (2)"), (t_ret + CLK_NS / 2, 15, "x6 = 42")],
              subtitle="fwd_a: 0 = register file, 1 = EX/MEM, 2 = MEM/WB. One stall cycle, then the loaded 41 "
                       "is forwarded from MEM/WB into the addi.")

    sigs = simulate(vvp, "pipe_fwd", "p_branch_flush", wdir / "branch_fwd.vcd")
    t_rst = first_time(sigs["core_tb.rst"], lambda v: v == "0")
    t_red = first_time(sigs[core + "ex_redirect"], lambda v: v == "1")
    rows = [("clk", "core_tb.clk"), ("IF pc", core + "pc_f"), ("ID pc", core + "d_pc"), ("ID valid", core + "d_valid"),
            ("EX pc", core + "e_pc"), ("EX valid", core + "e_valid"), ("redirect", core + "ex_redirect"),
            ("target", core + "ex_target"), ("MEM pc", core + "m_pc"), ("MEM valid", core + "m_valid"),
            ("MEM store", core + "m_store"), ("store commit", core + "d_commit"),
            ("ret_valid", "core_tb.ret_valid"), ("ret_pc", "core_tb.ret_pc"), ("sig_value", "core_tb.sig_value")]
    a = t_red - 2 * CLK_NS
    draw_wave(sigs, rows, a, a + 9 * CLK_NS, "Taken branch at 0x0c squashes the younger sw and illegal word (pipe_fwd)",
              EVID / "04-branch-flush-wave.png", cycle0=t_rst - 5,
              notes=[(t_red + CLK_NS / 2, 6, "beq taken -> 0x1c"),
                     (t_red + 1.5 * CLK_NS, 3, "sw @0x10 squashed"),
                     (t_red + 1.5 * CLK_NS, 5, "bubble"),
                     (t_red + 3.5 * CLK_NS, 10, "stale sw, MEM valid=0: no commit"),
                     (t_red + 5.5 * CLK_NS, 11, "only store: sw @0x20")],
              subtitle="beq resolves in EX and clears the IF/ID and ID/EX valid bits. The wrong-path sw (0x10) "
                       "and .word 0 (0x14) never reach MEM: no store commit, no retirement, no illegal-instruction stop.")

    log = (BUILD / "regression.log").read_text().splitlines()
    head = [l for l in log[:4]]
    start = next(i for i, l in enumerate(log) if l.startswith("== trace buffer"))
    body = [l for l in log[start:] if not l.startswith("elapsed")]
    sample = [l for l in log if l.startswith("  pass demo") or l.startswith("  pass rand_1 ")]
    lines = ["PS> python tools/run_tests.py", ""] + head + ["  ..."] + sample + ["  ..."] + body
    text_image(lines, EVID / "05-regression.png", "Regression run", highlight=("RESULT", "programs="))

    status_lines = (BUILD / "trace" / "p_loaduse.txt").read_text().splitlines()
    res = json.loads((BUILD / "results.json").read_text())["results"]
    demo = {r["cfg"]: r for r in res if r["name"] == "demo"}
    off, on = demo["pipe_nofwd"]["cycles"], demo["pipe_fwd"]["cycles"]
    cyc = ["", f"Same firmware (demo.c), same {demo['pipe_fwd']['retired']} retired instructions and signature in both modes:",
           f"  forwarding off (interlock): {off} cycles, {demo['pipe_nofwd']['stalls']} stall cycles",
           f"  forwarding on:              {on} cycles, {demo['pipe_fwd']['stalls']} stall cycles",
           f"  cycle reduction = ({off} - {on}) / {off} = {(off - on) / off * 100:.1f}%"]
    lines = ["PS> vvp -n build/core_pipe_fwd.vvp +hex=... +tmask=1 +tpost=3 +tdump=build/trace/p_loaduse.tdump",
             "PS> python tools/trace_decode.py build/trace/p_loaduse.tdump", ""] + status_lines + cyc
    text_image(lines, EVID / "06-trace-demo.png", "Trace buffer: trigger on stall, freeze after 3 samples",
               highlight=("<== trigger",))

    for name in ("regression.log", "mutation.log"):
        if (BUILD / name).exists():
            (EVID / name).write_text((BUILD / name).read_text())
    for name in ("p_loaduse.txt", "p_branch_flush.txt"):
        (EVID / f"trace-{name}").write_text((BUILD / "trace" / name).read_text())
    for vcd in ("smoke_sc.vcd", "loaduse_fwd.vcd", "branch_fwd.vcd"):
        (EVID / vcd).write_bytes((wdir / vcd).read_bytes())
    print("evidence written to", EVID)


if __name__ == "__main__":
    main()
