.section .text.start, "ax"
.global _start
_start:
    lui  x10, 0x10
    lui  x4, 0x80000
    addi x1, x0, 41
    sw   x1, 0(x10)
    lw   x5, 0(x10)
    addi x6, x5, 1
    sw   x6, 0(x4)
    ebreak
