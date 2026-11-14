import random
import sys

POOL = [r for r in range(1, 29) if r not in (10, 11)]
ALU_R = ["add", "sub", "sll", "slt", "sltu", "xor", "srl", "sra", "or", "and"]
ALU_I = ["addi", "slti", "sltiu", "xori", "ori", "andi"]
SHIFT_I = ["slli", "srli", "srai"]
BRANCHES = ["beq", "bne", "blt", "bge", "bltu", "bgeu"]
LOADS = [("lb", 1), ("lh", 2), ("lw", 4), ("lbu", 1), ("lhu", 2)]
STORES = [("sb", 1), ("sh", 2), ("sw", 4)]
WINDOW = 128


class Gen:
    def __init__(self, seed):
        self.rng = random.Random(seed)
        self.lines = []
        self.label_id = 0
        self.last_rd = 1

    def emit(self, text):
        self.lines.append("    " + text)

    def label(self):
        self.label_id += 1
        return f"L{self.label_id}"

    def dst(self):
        r = self.rng.random()
        if r < 0.08:
            return 0
        rd = self.rng.choice(POOL)
        return rd

    def src(self):
        r = self.rng.random()
        if r < 0.35:
            return self.last_rd
        if r < 0.42:
            return 0
        return self.rng.choice(POOL)

    def set_last(self, rd):
        if rd != 0:
            self.last_rd = rd

    def alu(self):
        kind = self.rng.random()
        rd = self.dst()
        if kind < 0.45:
            op = self.rng.choice(ALU_R)
            self.emit(f"{op} x{rd}, x{self.src()}, x{self.src()}")
        elif kind < 0.75:
            op = self.rng.choice(ALU_I)
            imm = self.rng.choice([self.rng.randint(-2048, 2047), -1, 0, 1, 2047, -2048])
            self.emit(f"{op} x{rd}, x{self.src()}, {imm}")
        elif kind < 0.92:
            op = self.rng.choice(SHIFT_I)
            sh = self.rng.choice([0, 1, 31, self.rng.randint(0, 31)])
            self.emit(f"{op} x{rd}, x{self.src()}, {sh}")
        elif kind < 0.96:
            self.emit(f"lui x{rd}, {self.rng.randint(0, 0xFFFFF)}")
        else:
            self.emit(f"auipc x{rd}, {self.rng.randint(0, 0xFFFFF)}")
        self.set_last(rd)

    def load(self):
        op, size = self.rng.choice(LOADS)
        off = self.rng.randrange(-WINDOW, WINDOW, size)
        rd = self.dst()
        self.emit(f"{op} x{rd}, {off}(x10)")
        self.set_last(rd)

    def store(self):
        op, size = self.rng.choice(STORES)
        off = self.rng.randrange(-WINDOW, WINDOW, size)
        self.emit(f"{op} x{self.src()}, {off}(x10)")

    def fwd_branch(self):
        br = self.rng.choice(BRANCHES)
        target = self.label()
        self.emit(f"{br} x{self.src()}, x{self.src()}, {target}")
        for _ in range(self.rng.randint(1, 3)):
            self.alu()
        self.lines.append(f"{target}:")

    def loop(self):
        top = self.label()
        self.emit(f"addi x11, x0, {self.rng.randint(1, 4)}")
        self.lines.append(f"{top}:")
        for _ in range(self.rng.randint(1, 3)):
            if self.rng.random() < 0.3:
                self.load()
            else:
                self.alu()
        self.emit("addi x11, x11, -1")
        self.emit(f"bne x11, x0, {top}")

    def jal(self):
        target = self.label()
        rd = self.dst()
        self.emit(f"jal x{rd}, {target}")
        self.alu()
        self.lines.append(f"{target}:")
        self.set_last(rd)

    def jalr(self):
        target = self.label()
        base = self.rng.choice(POOL)
        rd = self.rng.choice([base, self.dst()])
        bias = self.rng.choice([0, 1])
        self.emit(f"lui x{base}, %hi({target})")
        self.emit(f"addi x{base}, x{base}, %lo({target})")
        if bias:
            self.emit(f"addi x{base}, x{base}, 1")
        self.emit(f"jalr x{rd}, 0(x{base})")
        self.alu()
        self.lines.append(f"{target}:")
        self.set_last(rd)

    def program(self, items):
        self.lines += ['.section .text.start, "ax"', ".global _start", "_start:"]
        self.emit("lui x10, 0x11")
        self.emit("addi x10, x10, -2048")
        for r in POOL:
            self.emit(f"li x{r}, {self.rng.getrandbits(32)}")
        for off in range(-WINDOW, WINDOW, 4):
            self.emit(f"sw x{self.rng.choice(POOL)}, {off}(x10)")
        actions = [(self.alu, 40), (self.load, 14), (self.store, 12), (self.fwd_branch, 10),
                   (self.loop, 5), (self.jal, 4), (self.jalr, 4)]
        funcs = [a for a, _ in actions]
        weights = [w for _, w in actions]
        for _ in range(items):
            self.rng.choices(funcs, weights)[0]()
        self.emit("addi x1, x1, 0")
        for r in POOL[1:]:
            self.emit(f"xor x1, x1, x{r}")
        self.emit("lui x11, 0x80000")
        self.emit("sw x1, 0(x11)")
        self.emit("ebreak")
        return "\n".join(self.lines) + "\n"


def generate(seed, items=180):
    return Gen(seed).program(items)


if __name__ == "__main__":
    seed = int(sys.argv[1]) if len(sys.argv) > 1 else 1
    sys.stdout.write(generate(seed))
