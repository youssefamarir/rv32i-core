import re
import sys
from pathlib import Path

FIELDS = [
    ("cycle", 16), ("v_if", 1), ("v_id", 1), ("v_ex", 1), ("v_mem", 1), ("v_wb", 1),
    ("pc_if", 16), ("pc_id", 16), ("pc_ex", 16), ("pc_mem", 16), ("pc_wb", 16),
    ("fwd_a", 2), ("fwd_b", 2), ("stall", 2), ("redirect", 1), ("target", 16), ("stop", 4),
]
FWD = {0: "reg", 1: "MEM", 2: "WB", 3: "?"}
STALL = {0: "-", 1: "load-use", 2: "raw", 3: "?"}


def unpack(value):
    out = {}
    pos = 128
    for name, width in FIELDS:
        pos -= width
        out[name] = (value >> pos) & ((1 << width) - 1)
    return out


def load(path):
    status = {}
    raw = {}
    for line in Path(path).read_text().splitlines():
        if line.startswith("TSTATUS"):
            status = {k: int(v) for k, v in re.findall(r"(\w+)=(\d+)", line)}
        elif line.startswith("T "):
            _, idx, data = line.split()
            raw[int(idx)] = data
    depth = status["depth"]
    order = list(range(status["wptr"], depth)) + list(range(status["wptr"])) if status["wrapped"] \
        else list(range(status["wptr"]))
    samples = []
    for idx in order:
        s = unpack(int(raw[idx], 16))
        s["slot"] = idx
        s["is_trigger"] = bool(status["triggered"]) and idx == status["trig_idx"]
        samples.append(s)
    return status, samples


def table(status, samples):
    head = (f"trace depth={status['depth']} mask={status['mask']} post={status['post']} "
            f"triggered={status['triggered']} frozen={status['frozen']} samples={len(samples)}")
    cols = "cycle  IF        ID        EX        MEM       WB        fwdA fwdB stall     redirect"
    lines = [head, cols]
    for s in samples:
        def stage(v, pc):
            return f"{pc:04x}" + (" " if v else "x") + "    "
        red = f"-> {s['target']:04x}" if s["redirect"] else "-"
        mark = "  <== trigger" if s["is_trigger"] else ""
        lines.append(
            f"{s['cycle']:5d}  " + stage(s["v_if"], s["pc_if"]) + stage(s["v_id"], s["pc_id"])
            + stage(s["v_ex"], s["pc_ex"]) + stage(s["v_mem"], s["pc_mem"]) + stage(s["v_wb"], s["pc_wb"])
            + f"{FWD[s['fwd_a']]:<5}{FWD[s['fwd_b']]:<5}{STALL[s['stall']]:<10}{red}{mark}")
    lines.append("x after a PC marks an empty (invalid) stage")
    return "\n".join(lines)


if __name__ == "__main__":
    st, sm = load(sys.argv[1])
    print(table(st, sm))
