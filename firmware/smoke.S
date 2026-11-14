.section .text.start, "ax"
.global _start
_start:
    addi x1, x0, 7
    addi x2, x1, -2
    add  x3, x1, x2
    lui  x4, 0x80000
    sw   x3, 0(x4)
    addi x0, x3, 0
    ebreak
