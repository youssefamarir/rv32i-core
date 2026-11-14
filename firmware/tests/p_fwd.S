.section .text.start, "ax"
.global _start
_start:
    lui  x4, 0x80000
    addi x5, x0, 41
    addi x5, x5, 1
    add  x6, x5, x5
    sw   x6, 0(x4)
    ebreak
