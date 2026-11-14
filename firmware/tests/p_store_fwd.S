.section .text.start, "ax"
.global _start
_start:
    lui  x10, 0x10
    lui  x4, 0x80000
    addi x7, x0, 0x5a
    sw   x7, 0(x10)
    addi x8, x0, 0x3c
    addi x0, x0, 0
    sb   x8, 1(x10)
    addi x9, x0, 0x11
    addi x0, x0, 0
    addi x0, x0, 0
    sb   x9, 2(x10)
    lw   x11, 0(x10)
    sw   x11, 4(x10)
    lw   x12, 4(x10)
    addi x13, x10, 8
    sh   x12, 0(x13)
    lw   x14, 8(x10)
    add  x15, x12, x14
    sw   x15, 0(x4)
    ebreak
