.section .text.start, "ax"
.global _start
_start:
    lui  x1, 0x20
    lui  x4, 0x80000
    lw   x3, 0(x1)
    jal  x5, away
    ebreak
away:
    addi x6, x0, 1
    sw   x6, 0(x4)
    ebreak
