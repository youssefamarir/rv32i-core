.section .text.start, "ax"
.global _start
_start:
    lui  x4, 0x80000
    lui  x10, 0x10
    addi x1, x0, 3
    lh   x2, 1(x10)
    beq  x0, x0, skip
    sw   x1, 0(x4)
skip:
    sw   x1, 0(x4)
    ebreak
