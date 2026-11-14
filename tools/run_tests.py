import argparse
import json
import os
import platform
import re
import shutil
import subprocess
import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
BUILD = ROOT / "build"
sys.path.insert(0, str(ROOT / "tools"))

import demo_expected
import gen_random
import mkhex
import refmodel
import trace_decode

CONFIGS = [("sc", 0, 1), ("pipe_nofwd", 1, 0), ("pipe_fwd", 1, 1)]
GCC_NAMES = ["riscv32-esp-elf-gcc", "riscv32-unknown-elf-gcc", "riscv64-unknown-elf-gcc",
             "riscv-none-elf-gcc", "riscv32-elf-gcc", "riscv64-elf-gcc"]
GCC_DIRS = [Path.home() / ".platformio" / "packages" / "toolchain-riscv32-esp" / "bin"]
SIM_DIRS = [Path("C:/msys64/ucrt64/bin")]
RV32I = {"lui", "auipc", "jal", "jalr", "beq", "bne", "blt", "bge", "bltu", "bgeu",
         "lb", "lh", "lw", "lbu", "lhu", "sb", "sh", "sw", "addi", "slti", "sltiu", "xori",
         "ori", "andi", "slli", "srli", "srai", "add", "sub", "sll", "slt", "sltu", "xor",
         "srl", "sra", "or", "and", "fence", "ecall", "ebreak"}


class Log:
    def __init__(self, path):
        path.parent.mkdir(parents=True, exist_ok=True)
        self.fh = path.open("w", encoding="utf-8")

    def __call__(self, text=""):
        print(text, flush=True)
        self.fh.write(text + "\n")
        self.fh.flush()


def find_in(dirs, name):
    for d in dirs:
        for cand in (d / name, d / (name + ".exe")):
            if cand.is_file():
                return str(cand)
    return None


def find_gcc():
    if os.environ.get("RV_GCC"):
        return os.environ["RV_GCC"]
    for n in GCC_NAMES:
        p = shutil.which(n)
        if p:
            return p
    for n in GCC_NAMES:
        p = find_in(GCC_DIRS, n)
        if p:
            return p
    raise SystemExit("RISC-V GCC not found. Set RV_GCC to the full path of the gcc executable.")


def sibling(gcc, tool):
    p = Path(gcc)
    return str(p.with_name(re.sub(r"gcc(\.exe)?$", lambda m: tool + (m.group(1) or ""), p.name)))


def find_sim():
    dirs = [Path(os.environ["SIM_BIN"])] if os.environ.get("SIM_BIN") else []
    found = {}
    for tool in ("iverilog", "vvp"):
        found[tool] = find_in(dirs, tool) or shutil.which(tool) or find_in(SIM_DIRS, tool)
        if not found[tool]:
            raise SystemExit(f"{tool} not found. Set SIM_BIN to the folder containing iverilog and vvp.")
    bindir = str(Path(found["iverilog"]).parent)
    os.environ["PATH"] = bindir + os.pathsep + os.environ.get("PATH", "")
    return found["iverilog"], found["vvp"]


def run(cmd, timeout=300, cwd=ROOT):
    return subprocess.run(cmd, cwd=cwd, capture_output=True, text=True, timeout=timeout)


def rel(p):
    return Path(os.path.relpath(p, ROOT)).as_posix()


class Regression:
    def __init__(self, args, log):
        self.args = args
        self.log = log
        self.gcc = find_gcc()
        self.objcopy = sibling(self.gcc, "objcopy")
        self.objdump = sibling(self.gcc, "objdump")
        self.iverilog, self.vvp = find_sim()
        self.failures = []
        self.results = []
        self.compared = 0
        self.runs = 0
        self.groups = {}
        self.configs = [c for c in CONFIGS if not args.configs or c[0] in args.configs]

    def fail(self, what):
        self.failures.append(what)
        self.log(f"  FAIL {what}")

    def versions(self):
        gcc_v = run([self.gcc, "--version"]).stdout.splitlines()[0]
        iv_v = run([self.iverilog, "-V"]).stdout.splitlines()[0]
        self.log(f"host     {platform.system()} {platform.release()} python {platform.python_version()}")
        self.log(f"gcc      {gcc_v}  ({self.gcc})")
        self.log(f"iverilog {iv_v}")

    def compile_rtl(self):
        self.vvps = {}
        for name, pipe, fwd in self.configs:
            out = BUILD / f"core_{name}.vvp"
            p = run([self.iverilog, "-g2012", "-Wall", "-s", "core_tb", "-P", f"core_tb.PIPELINE={pipe}",
                     "-P", f"core_tb.FORWARD={fwd}", "-o", rel(out), "-f", "sim/files.f"])
            warn = (p.stdout + p.stderr).strip()
            if p.returncode != 0:
                self.log(warn)
                raise SystemExit(f"RTL compilation failed for {name}")
            self.vvps[name] = out
            self.log(f"compiled {name:<11} PIPELINE={pipe} FORWARD={fwd}" + (f"  warnings:\n{warn}" if warn else ""))

    def build(self, name, srcs, kind, outdir):
        outdir.mkdir(parents=True, exist_ok=True)
        elf, dis, binf, hexf = (outdir / f"{name}{e}" for e in (".elf", ".dis", ".bin", ".hex"))
        cmd = [self.gcc, "-march=rv32i", "-mabi=ilp32", "-nostdlib", "-nostartfiles", "-mno-relax",
               "-Wl,--no-relax", "-T", "firmware/link.ld", "-I", "firmware/tests"]
        if kind == "c":
            cmd += ["-O2", "-ffreestanding", "-fno-pic", "-msmall-data-limit=0"]
        cmd += ["-o", rel(elf)] + [rel(Path(s)) if Path(s).is_absolute() else s for s in srcs]
        p = run(cmd)
        if p.returncode != 0:
            raise RuntimeError(f"build of {name} failed:\n{p.stdout}{p.stderr}")
        (outdir / f"{name}.cmd").write_text(" ".join(cmd) + "\n")
        d = run([self.objdump, "-d", "-M", "no-aliases", rel(elf)])
        dis.write_text(d.stdout)
        p = run([self.objcopy, "-O", "binary", rel(elf), rel(binf)])
        if p.returncode != 0:
            raise RuntimeError(f"objcopy failed for {name}: {p.stderr}")
        words = mkhex.convert(binf, hexf)
        if kind == "c":
            self.isa_check(name, elf, d.stdout)
        return {"elf": elf, "dis": dis, "hex": hexf, "words": words}

    def isa_check(self, name, elf, dis):
        syms = run([self.objdump, "-t", rel(elf)]).stdout
        funcs = {line.split()[-1] for line in syms.splitlines() if " F " in line}
        hdr = run([self.objdump, "-h", rel(elf)]).stdout
        for m in re.finditer(r"^\s*\d+\s+(\S+)\s+([0-9a-f]+)\s+([0-9a-f]+)\s+[0-9a-f]+", hdr, re.M):
            sec, size, vma = m.group(1), int(m.group(2), 16), int(m.group(3), 16)
            if size and not (vma + size <= 0x1000 or 0x10000 <= vma and vma + size <= 0x11000):
                self.fail(f"{name}: section {sec} at {vma:#x} is outside the memory map")
        bad = set()
        current = None
        for line in dis.splitlines():
            m = re.match(r"^[0-9a-f]+ <(.+)>:", line)
            if m:
                current = m.group(1)
                continue
            m = re.match(r"^\s+[0-9a-f]+:\s+[0-9a-f]{8}\s+(\S+)", line)
            if m and (current in funcs or current == "_start") and m.group(1) not in RV32I:
                bad.add(m.group(1))
        if bad:
            self.fail(f"{name}: instructions outside RV32I: {sorted(bad)}")
        else:
            self.log(f"  isa-check {name}: functions {sorted(funcs)} use RV32I only, sections inside the map")

    def run_rtl(self, cfg, prog, exp, outdir, vcd=False, extra=()):
        trace = outdir / f"{cfg}.trace"
        cmd = [self.vvp, "-n", rel(self.vvps[cfg]), f"+hex={rel(prog['hex'])}", f"+trace={rel(trace)}",
               f"+timeout={exp['timeout']}", f"+cause={exp['cause']}"]
        cmd.append(f"+sig={exp['sig']:08x}" if exp.get("sig") is not None else "+nosig")
        if exp.get("nosigwrite"):
            cmd.append("+nosigwrite")
        if exp.get("pc") is not None:
            cmd.append(f"+stoppc={exp['pc']:08x}")
        cmd.append(f"+vcd={rel(outdir / (cfg + '.vcd'))}" if vcd else "+novcd")
        cmd += list(extra)
        t0 = time.time()
        p = run(cmd, timeout=self.args.sim_timeout)
        out = p.stdout + p.stderr
        res = {"cfg": cfg, "ok": p.returncode == 0 and "\nPASS" in "\n" + out, "out": out,
               "seconds": round(time.time() - t0, 3)}
        m = re.search(r"PERF cycles=(\d+) retired=(\d+) stalls=(\d+) flushes=(\d+)", out)
        if m:
            res.update(cycles=int(m[1]), retired=int(m[2]), stalls=int(m[3]), flushes=int(m[4]))
        m = re.search(r"SIG written=(\d) value=(\S+) writes=(\d+)", out)
        if m:
            res.update(sig_written=int(m[1]), sig=m[2], sig_writes=int(m[3]))
        m = re.search(r"STOP cause=(\S+) pc=(\S+)", out)
        if m:
            res.update(stop=m[1], stop_pc=m[2])
        res["trace"] = trace.read_text().splitlines() if trace.exists() else []
        return res

    def disasm_at(self, dis_text, pc):
        for line in dis_text.splitlines():
            m = re.match(r"^\s+([0-9a-f]+):\s+(.*)$", line)
            if m and int(m.group(1), 16) == pc:
                return m.group(2).strip()
        return "?"

    def check_program(self, name, prog, exp, outdir, seed=None):
        machine, ref = refmodel.run(prog["words"])
        for g, n in machine.groups.items():
            self.groups[g] = self.groups.get(g, 0) + n
        if self.args.inject_mismatch and ref and ref[0].startswith("R"):
            parts = ref[0].split()
            if parts[5] != "--------":
                parts[5] = f"{int(parts[5], 16) ^ 1:08x}"
                ref[0] = " ".join(parts)
        (outdir / "ref.trace").write_text("\n".join(ref) + "\n")
        ref_stop = ref[-1].split()
        ref_cause, ref_pc = int(ref_stop[1]), int(ref_stop[2], 16)
        if ref_cause != exp["cause"] or (exp.get("pc") is not None and ref_pc != exp["pc"]):
            self.fail(f"{name}: reference model stopped with cause {ref_cause} pc {ref_pc:08x}, "
                      f"test expects cause {exp['cause']} pc {exp.get('pc')}")
        if exp.get("sig") is not None and machine.sig != exp["sig"]:
            self.fail(f"{name}: reference signature {machine.sig} differs from expected {exp['sig']:08x}")
        dis_text = prog["dis"].read_text()
        traces = {}
        for cfg, _, _ in self.configs:
            res = self.run_rtl(cfg, prog, exp, outdir, vcd=self.args.vcd)
            self.runs += 1
            res["name"] = name
            ok = res["ok"]
            why = ""
            if not ok:
                fl = re.search(r"FAIL[^\n]*", res["out"])
                why = fl.group(0) if fl else "simulation did not report PASS"
            rtl = res["trace"]
            if ok and len(rtl) != len(ref):
                ok = False
                why = f"record count {len(rtl)} vs reference {len(ref)}"
            if ok or rtl:
                for i, (a, b) in enumerate(zip(rtl, ref)):
                    if a != b:
                        ok = False
                        pc = int(b.split()[2 if b[0] == "R" else 2], 16)
                        why = (f"first mismatch at record {i} pc {pc:08x} [{self.disasm_at(dis_text, pc)}]"
                               f"\n      rtl: {a}\n      ref: {b}" + (f"\n      seed: {seed}" if seed is not None else ""))
                        break
                else:
                    if len(rtl) == len(ref):
                        self.compared += len(ref)
            for key, field in (("stalls", "stalls"), ("flushes", "flushes")):
                want = exp.get(key, {}).get(cfg)
                if ok and want is not None and res.get(field) != want:
                    ok = False
                    why = f"{field} {res.get(field)} expected {want}"
            if ok and exp.get("sig_writes") is not None and res.get("sig_writes") != exp["sig_writes"]:
                ok = False
                why = f"signature writes {res.get('sig_writes')} expected {exp['sig_writes']}"
            res["pass"] = ok
            traces[cfg] = rtl
            self.results.append({k: v for k, v in res.items() if k not in ("out", "trace")})
            tag = "pass" if ok else "FAIL"
            perf = f"cycles={res.get('cycles', '?'):>6} retired={res.get('retired', '?'):>5}"
            if cfg != "sc":
                perf += f" stalls={res.get('stalls', '?'):>4} flushes={res.get('flushes', '?'):>4}"
            self.log(f"  {tag} {name:<26} {cfg:<11} {perf}")
            if not ok:
                self.fail(f"{name} [{cfg}]: {why}")
                self.save_failure(name, cfg, prog, exp, outdir, seed)
        if len({tuple(t) for t in traces.values()}) > 1 and not self.args.inject_mismatch:
            self.fail(f"{name}: retirement streams differ between configurations")

    def save_failure(self, name, cfg, prog, exp, outdir, seed):
        dest = BUILD / "fail" / f"{name}_{cfg}"
        dest.mkdir(parents=True, exist_ok=True)
        for f in [prog["dis"], outdir / "ref.trace", outdir / f"{cfg}.trace"] + list(outdir.glob("*.S")):
            if f.exists():
                shutil.copy(f, dest / f.name)
        self.run_rtl(cfg, prog, exp, dest, vcd=True)
        if seed is not None:
            (dest / "seed.txt").write_text(f"{seed}\n")
        self.log(f"      saved disassembly, traces and waveform in {rel(dest)}")

    def expectations(self, t):
        sig = t.get("sig")
        if sig == "from:demo_expected":
            sig = demo_expected.expected()
        elif sig is not None:
            sig = int(sig, 16)
        if self.args.inject_failure and t["name"] == "smoke":
            sig ^= 1
        return {"sig": sig, "cause": refmodel.CAUSES[t["cause"]], "pc": int(t["pc"], 16) if "pc" in t else None,
                "nosigwrite": t.get("nosigwrite", False), "timeout": t.get("timeout", 2000),
                "stalls": t.get("stalls", {}), "flushes": t.get("flushes", {}),
                "sig_writes": t.get("sig_writes")}

    def directed(self, manifest):
        self.log("\n== directed tests ==")
        for t in manifest["tests"]:
            if self.args.only and t["name"] not in self.args.only:
                continue
            outdir = BUILD / "tests" / t["name"]
            prog = self.build(t["name"], t["src"], t.get("kind", "asm"), outdir)
            self.check_program(t["name"], prog, self.expectations(t), outdir)

    def random_tests(self, manifest):
        cfg = manifest["random"]
        seeds = self.args.seeds or cfg["seeds"]
        self.log(f"\n== random programs (seeds {seeds}) ==")
        for seed in seeds:
            name = f"rand_{seed}"
            outdir = BUILD / "random" / name
            outdir.mkdir(parents=True, exist_ok=True)
            src = outdir / f"{name}.S"
            src.write_text(gen_random.generate(seed, cfg["items"]))
            prog = self.build(name, [str(src)], "asm", outdir)
            machine, _ = refmodel.run(prog["words"])
            exp = {"sig": machine.sig, "cause": refmodel.CAUSES["EBREAK"], "pc": None, "nosigwrite": False,
                   "timeout": cfg["timeout"], "stalls": {}, "flushes": {}, "sig_writes": None}
            self.check_program(name, prog, exp, outdir, seed=seed)

    def trace_tests(self):
        self.log("\n== trace buffer ==")
        out = BUILD / "trace_tb.vvp"
        p = run([self.iverilog, "-g2012", "-Wall", "-s", "trace_tb", "-o", rel(out), "rtl/rv_trace.sv", "sim/trace_tb.sv"])
        if p.returncode != 0:
            self.fail(f"trace_tb compile: {p.stdout}{p.stderr}")
            return
        p = run([self.vvp, "-n", rel(out)])
        self.runs += 1
        if p.returncode == 0 and "PASS trace_tb" in p.stdout:
            self.log("  pass trace_tb (capture, wrap, enable, masked trigger, post window, freeze, rearm, reset)")
        else:
            self.fail(f"trace_tb: {p.stdout.strip()}")
        if "pipe_fwd" not in [c[0] for c in self.configs]:
            return
        cases = [("p_loaduse", 1, 3, "stall", 1), ("p_branch_flush", 2, 2, "redirect", 1)]
        manifest = {t["name"]: t for t in json.loads((ROOT / "tools" / "tests.json").read_text())["tests"]}
        tdir = BUILD / "trace"
        tdir.mkdir(parents=True, exist_ok=True)
        for test, mask, post, field, want in cases:
            t = manifest[test]
            prog = self.build(test, t["src"], "asm", tdir / test)
            dump = tdir / f"{test}.tdump"
            res = self.run_rtl("pipe_fwd", prog, self.expectations(t), tdir / test, vcd=True,
                               extra=[f"+tmask={mask}", f"+tpost={post}", f"+tdump={rel(dump)}"])
            self.runs += 1
            if not res["ok"]:
                self.fail(f"trace capture {test}: simulation failed")
                continue
            status, samples = trace_decode.load(dump)
            text = trace_decode.table(status, samples)
            (tdir / f"{test}.txt").write_text(text + "\n")
            trig = [i for i, s in enumerate(samples) if s["is_trigger"]]
            problems = []
            if not (status["triggered"] and status["frozen"]):
                problems.append("buffer did not trigger and freeze")
            elif len(trig) != 1:
                problems.append("trigger sample missing")
            else:
                ts = samples[trig[0]]
                after = len(samples) - 1 - trig[0]
                if (ts[field] != want if field == "redirect" else ts[field] == 0):
                    problems.append(f"trigger sample has no {field}")
                if after != post:
                    problems.append(f"{after} samples after trigger, expected {post}")
                if any(samples[i + 1]["cycle"] != samples[i]["cycle"] + 1 for i in range(len(samples) - 1)):
                    problems.append("captured cycles are not consecutive")
                earlier = [s for s in samples[:trig[0]] if (s["stall"] if mask == 1 else s["redirect"])]
                if earlier:
                    problems.append("an earlier matching event was not the trigger")
            if problems:
                self.fail(f"trace capture {test}: {'; '.join(problems)}")
            else:
                ts = samples[trig[0]]
                self.log(f"  pass trace capture {test:<15} mask={mask} post={post} trigger at cycle {ts['cycle']}, "
                         f"{post} post-trigger samples, frozen  ({rel(tdir / (test + '.txt'))})")

    def selftest(self):
        self.log("\n== checker self-test ==")
        for flag, what in (("--inject-failure", "wrong expected signature"),
                           ("--inject-mismatch", "corrupted reference record")):
            p = run([sys.executable, str(Path(__file__)), "--only", "smoke", "--configs", "sc",
                     "--no-selftest", "--no-random", "--no-trace", flag,
                     "--log", rel(BUILD / f"selftest{flag.replace('--', '_')}.log")], timeout=600)
            self.runs += 1
            if p.returncode != 0:
                self.log(f"  pass {what}: regression exited with code {p.returncode} as required")
            else:
                self.fail(f"self-test {flag}: regression passed but should have failed")

    def report(self):
        self.log("\n== summary ==")
        self.log("instruction groups executed by the reference model: "
                 + ", ".join(f"{g}={n}" for g, n in sorted(self.groups.items())))
        rows = {}
        for r in self.results:
            rows.setdefault(r["name"], {})[r["cfg"]] = r
        cfgs = [c[0] for c in self.configs]
        show = [n for n in rows if n == "demo" or n.startswith("rand_")]
        if show and len(cfgs) == 3:
            self.log("\ncycles (identical retirement stream and signature in every configuration)")
            self.log(f"{'workload':<12}{'retired':>9}" + "".join(f"{c:>12}" for c in cfgs) + f"{'reduction':>11}")
            tot = {c: 0 for c in cfgs}
            for n in show:
                r = rows[n]
                if not all(c in r and r[c].get("pass") for c in cfgs):
                    continue
                off, on = r["pipe_nofwd"]["cycles"], r["pipe_fwd"]["cycles"]
                for c in cfgs:
                    tot[c] += r[c]["cycles"]
                self.log(f"{n:<12}{r['sc']['retired']:>9}" + "".join(f"{r[c]['cycles']:>12}" for c in cfgs)
                         + f"{(off - on) / off * 100:>10.1f}%")
            if tot["pipe_nofwd"]:
                self.log(f"{'total':<12}{'':>9}" + "".join(f"{tot[c]:>12}" for c in cfgs)
                         + f"{(tot['pipe_nofwd'] - tot['pipe_fwd']) / tot['pipe_nofwd'] * 100:>10.1f}%")
        (BUILD / "results.json").write_text(json.dumps(
            {"results": self.results, "compared": self.compared, "runs": self.runs, "groups": self.groups,
             "failures": self.failures}, indent=1))
        n_prog = len(rows)
        self.log(f"\nprograms={n_prog} simulations={self.runs} compared_events={self.compared} "
                 f"configs={','.join(cfgs)} failures={len(self.failures)}")
        if self.failures:
            self.log("RESULT: FAIL")
            for f in self.failures:
                self.log(f"  - {f.splitlines()[0]}")
        else:
            self.log("RESULT: PASS")


def main():
    ap = argparse.ArgumentParser(description="RV32I regression: build, simulate, compare against the reference model")
    ap.add_argument("--only", type=lambda s: s.split(","), help="comma-separated directed test names")
    ap.add_argument("--configs", type=lambda s: s.split(","), help="subset of sc,pipe_nofwd,pipe_fwd")
    ap.add_argument("--seeds", type=lambda s: [int(x) for x in s.split(",")], help="random seeds to run")
    ap.add_argument("--no-random", action="store_true")
    ap.add_argument("--no-trace", action="store_true")
    ap.add_argument("--no-selftest", action="store_true")
    ap.add_argument("--vcd", action="store_true", help="dump a VCD for every simulation")
    ap.add_argument("--inject-failure", action="store_true", help="break the smoke test's expected signature")
    ap.add_argument("--inject-mismatch", action="store_true", help="corrupt the first reference record")
    ap.add_argument("--sim-timeout", type=int, default=300, help="wall-clock seconds per simulation")
    ap.add_argument("--log", default="build/regression.log")
    args = ap.parse_args()

    log = Log(ROOT / args.log)
    t0 = time.time()
    log("RV32I regression  " + " ".join(sys.argv[1:]))
    reg = Regression(args, log)
    reg.versions()
    reg.compile_rtl()
    manifest = json.loads((ROOT / "tools" / "tests.json").read_text())
    reg.directed(manifest)
    if not args.no_random and not args.only:
        reg.random_tests(manifest)
    if not args.no_trace and not args.only:
        reg.trace_tests()
    if not args.no_selftest and not args.only:
        reg.selftest()
    reg.report()
    log(f"elapsed {time.time() - t0:.1f}s")
    sys.exit(1 if reg.failures else 0)


if __name__ == "__main__":
    main()
