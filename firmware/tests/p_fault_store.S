.section .text.start, "ax"
.global _start
_start:
    lui  x1, 0x20
    lui  x4, 0x80000
    addi x2, x0, 9
    lw   x3, 0(x1)
    sw   x2, 0(x4)
    addi x5, x0, 1
    ebreak
