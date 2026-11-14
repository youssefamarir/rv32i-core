import sys
from collections import Counter

ROM_BASE, ROM_SIZE = 0x00000000, 0x1000
RAM_BASE, RAM_SIZE = 0x00010000, 0x1000
SIG_ADDR = 0x80000000
MASK = 0xFFFFFFFF

CAUSES = {
    "EBREAK": 1,
    "ECALL": 2,
    "ILLEGAL": 3,
    "INST_MISALIGNED": 4,
    "FETCH_ACCESS": 5,
    "LOAD_MISALIGNED": 6,
    "LOAD_ACCESS": 7,
    "STORE_MISALIGNED": 8,
    "STORE_ACCESS": 9,
}
CAUSE_NAMES = {v: k for k, v in CAUSES.items()}


class Stop(Exception):
    def __init__(self, cause):
        super().__init__(cause)
        self.cause = cause


def sext(value, bits):
    value &= (1 << bits) - 1
    return value - (1 << bits) if value >> (bits - 1) else value


def field(word, hi, lo):
    return (word >> lo) & ((1 << (hi - lo + 1)) - 1)


class Machine:
    def __init__(self, rom_words):
        self.rom = bytearray()
        for w in rom_words[:ROM_SIZE // 4]:
            self.rom += (w & MASK).to_bytes(4, "little")
        self.rom = self.rom.ljust(ROM_SIZE, b"\x00")
        self.ram = bytearray(RAM_SIZE)
        self.sig = None
        self.sig_writes = 0
        self.x = [0] * 32
        self.pc = ROM_BASE
        self.seq = 0
        self.groups = Counter()
        self.mnemonics = Counter()

    def reg(self, i):
        return 0 if i == 0 else self.x[i]

    def region(self, addr, size, store):
        if store:
            if RAM_BASE <= addr < RAM_BASE + RAM_SIZE:
                return "ram"
            if addr == SIG_ADDR and size == 4:
                return "sig"
            return None
        if ROM_BASE <= addr < ROM_BASE + ROM_SIZE:
            return "rom"
        if RAM_BASE <= addr < RAM_BASE + RAM_SIZE:
            return "ram"
        if addr == SIG_ADDR and size == 4:
            return "sig"
        return None

    def load(self, addr, size, signed):
        if addr % size:
            raise Stop(CAUSES["LOAD_MISALIGNED"])
        where = self.region(addr, size, False)
        if where is None:
            raise Stop(CAUSES["LOAD_ACCESS"])
        if where == "sig":
            raw = self.sig or 0
        else:
            mem, base = (self.rom, ROM_BASE) if where == "rom" else (self.ram, RAM_BASE)
            off = addr - base
            raw = int.from_bytes(mem[off:off + size], "little")
        return sext(raw, size * 8) & MASK if signed else raw

    def store(self, addr, size, value):
        if addr % size:
            raise Stop(CAUSES["STORE_MISALIGNED"])
        where = self.region(addr, size, True)
        if where is None:
            raise Stop(CAUSES["STORE_ACCESS"])
        lane = addr & 3
        be = ((1 << size) - 1) << lane
        data = ((value & ((1 << (8 * size)) - 1)) << (8 * lane)) & MASK
        return where, addr & ~3, be, data, value & ((1 << (8 * size)) - 1)

    def commit_store(self, where, addr, size, raw):
        if where == "sig":
            self.sig = raw & MASK
            self.sig_writes += 1
        else:
            off = addr - RAM_BASE
            self.ram[off:off + size] = raw.to_bytes(size, "little")

    def fetch(self):
        if not (ROM_BASE <= self.pc < ROM_BASE + ROM_SIZE):
            raise Stop(CAUSES["FETCH_ACCESS"])
        off = self.pc - ROM_BASE
        return int.from_bytes(self.rom[off:off + 4], "little")

    def step(self):
        pc = self.pc
        inst = 0
        try:
            inst = self.fetch()
            rd_write, store, next_pc = self.execute(pc, inst)
        except Stop as stop:
            return ("S", stop.cause, pc)
        if rd_write is not None and rd_write[0] != 0:
            self.x[rd_write[0]] = rd_write[1] & MASK
            rd_rec = rd_write
        else:
            rd_rec = None
        st_rec = None
        if store is not None:
            where, aligned, be, data, raw, addr, size = store
            self.commit_store(where, addr, size, raw)
            st_rec = (aligned, be, data)
        rec = ("R", self.seq, pc, inst, rd_rec, st_rec)
        self.seq += 1
        self.pc = next_pc & MASK
        return rec

    def execute(self, pc, inst):
        if inst & 3 != 3:
            raise Stop(CAUSES["ILLEGAL"])
        op = field(inst, 6, 2)
        rd = field(inst, 11, 7)
        f3 = field(inst, 14, 12)
        rs1 = field(inst, 19, 15)
        rs2 = field(inst, 24, 20)
        f7 = field(inst, 31, 25)
        a = self.reg(rs1)
        b = self.reg(rs2)
        nxt = pc + 4

        if op == 0b01101:
            self.note("upper", "lui")
            return (rd, inst & 0xFFFFF000), None, nxt
        if op == 0b00101:
            self.note("upper", "auipc")
            return (rd, (pc + (inst & 0xFFFFF000)) & MASK), None, nxt
        if op == 0b11011:
            off = sext((field(inst, 31, 31) << 20) | (field(inst, 19, 12) << 12)
                       | (field(inst, 20, 20) << 11) | (field(inst, 30, 21) << 1), 21)
            tgt = (pc + off) & MASK
            if tgt & 3:
                raise Stop(CAUSES["INST_MISALIGNED"])
            self.note("jump", "jal")
            return (rd, nxt & MASK), None, tgt
        if op == 0b11001:
            if f3 != 0:
                raise Stop(CAUSES["ILLEGAL"])
            tgt = (a + sext(field(inst, 31, 20), 12)) & MASK & ~1
            if tgt & 3:
                raise Stop(CAUSES["INST_MISALIGNED"])
            self.note("jump", "jalr")
            return (rd, nxt & MASK), None, tgt
        if op == 0b11000:
            sa, sb = sext(a, 32), sext(b, 32)
            conds = {0: ("beq", a == b), 1: ("bne", a != b), 4: ("blt", sa < sb),
                     5: ("bge", sa >= sb), 6: ("bltu", a < b), 7: ("bgeu", a >= b)}
            if f3 not in conds:
                raise Stop(CAUSES["ILLEGAL"])
            name, taken = conds[f3]
            off = sext((field(inst, 31, 31) << 12) | (field(inst, 7, 7) << 11)
                       | (field(inst, 30, 25) << 5) | (field(inst, 11, 8) << 1), 13)
            tgt = (pc + off) & MASK
            if taken and tgt & 3:
                raise Stop(CAUSES["INST_MISALIGNED"])
            self.note("branch", name)
            return None, None, tgt if taken else nxt
        if op == 0b00000:
            kinds = {0: ("lb", 1, True), 1: ("lh", 2, True), 2: ("lw", 4, False),
                     4: ("lbu", 1, False), 5: ("lhu", 2, False)}
            if f3 not in kinds:
                raise Stop(CAUSES["ILLEGAL"])
            name, size, signed = kinds[f3]
            addr = (a + sext(field(inst, 31, 20), 12)) & MASK
            value = self.load(addr, size, signed)
            self.note("load", name)
            return (rd, value), None, nxt
        if op == 0b01000:
            kinds = {0: ("sb", 1), 1: ("sh", 2), 2: ("sw", 4)}
            if f3 not in kinds:
                raise Stop(CAUSES["ILLEGAL"])
            name, size = kinds[f3]
            off = sext((field(inst, 31, 25) << 5) | field(inst, 11, 7), 12)
            addr = (a + off) & MASK
            where, aligned, be, data, raw = self.store(addr, size, b)
            self.note("store", name)
            return None, (where, aligned, be, data, raw, addr, size), nxt
        if op == 0b00100:
            imm = sext(field(inst, 31, 20), 12) & MASK
            sh = field(inst, 24, 20)
            if f3 == 0:
                name, val = "addi", a + imm
            elif f3 == 2:
                name, val = "slti", int(sext(a, 32) < sext(imm, 32))
            elif f3 == 3:
                name, val = "sltiu", int(a < imm)
            elif f3 == 4:
                name, val = "xori", a ^ imm
            elif f3 == 6:
                name, val = "ori", a | imm
            elif f3 == 7:
                name, val = "andi", a & imm
            elif f3 == 1:
                if f7 != 0:
                    raise Stop(CAUSES["ILLEGAL"])
                name, val = "slli", a << sh
            else:
                if f7 == 0:
                    name, val = "srli", a >> sh
                elif f7 == 0x20:
                    name, val = "srai", sext(a, 32) >> sh
                else:
                    raise Stop(CAUSES["ILLEGAL"])
            self.note("alu_imm", name)
            return (rd, val & MASK), None, nxt
        if op == 0b01100:
            sh = b & 31
            table = {
                (0x00, 0): ("add", lambda: a + b),
                (0x20, 0): ("sub", lambda: a - b),
                (0x00, 1): ("sll", lambda: a << sh),
                (0x00, 2): ("slt", lambda: int(sext(a, 32) < sext(b, 32))),
                (0x00, 3): ("sltu", lambda: int(a < b)),
                (0x00, 4): ("xor", lambda: a ^ b),
                (0x00, 5): ("srl", lambda: a >> sh),
                (0x20, 5): ("sra", lambda: sext(a, 32) >> sh),
                (0x00, 6): ("or", lambda: a | b),
                (0x00, 7): ("and", lambda: a & b),
            }
            if (f7, f3) not in table:
                raise Stop(CAUSES["ILLEGAL"])
            name, fn = table[(f7, f3)]
            self.note("alu_reg", name)
            return (rd, fn() & MASK), None, nxt
        if op == 0b00011:
            if f3 != 0:
                raise Stop(CAUSES["ILLEGAL"])
            self.note("system", "fence")
            return None, None, nxt
        if op == 0b11100:
            if inst == 0x00000073:
                self.note("system", "ecall")
                raise Stop(CAUSES["ECALL"])
            if inst == 0x00100073:
                self.note("system", "ebreak")
                raise Stop(CAUSES["EBREAK"])
            raise Stop(CAUSES["ILLEGAL"])
        raise Stop(CAUSES["ILLEGAL"])

    def note(self, group, name):
        self.groups[group] += 1
        self.mnemonics[name] += 1


def format_record(rec):
    if rec[0] == "S":
        return f"S {rec[1]} {rec[2]:08x}"
    _, seq, pc, inst, rd, st = rec
    r = f"{rd[0]} {rd[1]:08x}" if rd else "-- --------"
    s = f"{st[0]:08x} {st[1]:x} {st[2]:08x}" if st else "-------- - --------"
    return f"R {seq} {pc:08x} {inst:08x} {r} {s}"


def run(rom_words, max_steps=200000):
    m = Machine(rom_words)
    lines = []
    for _ in range(max_steps):
        rec = m.step()
        lines.append(format_record(rec))
        if rec[0] == "S":
            return m, lines
    raise RuntimeError(f"reference model did not stop within {max_steps} instructions")


if __name__ == "__main__":
    sys.path.insert(0, __import__("os").path.dirname(__file__))
    import mkhex
    machine, out = run(mkhex.load_hex(sys.argv[1]))
    print("\n".join(out))
    print(f"SIG {machine.sig:08x}" if machine.sig is not None else "SIG none")
