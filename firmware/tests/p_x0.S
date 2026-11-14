.section .text.start, "ax"
.global _start
_start:
    lui  x10, 0x10
    lui  x4, 0x80000
    addi x1, x0, 7
    addi x0, x0, 0
    addi x0, x0, 0
    sw   x1, 0(x10)
    addi x0, x0, 0
    addi x0, x0, 0
    lw   x0, 0(x10)
    add  x6, x0, x0
    addi x0, x1, 1
    add  x7, x0, x0
    addi x0, x1, 3
    addi x0, x1, 3
    add  x8, x0, x0
    lui  x0, 0x12345
    or   x9, x0, x0
    addi x0, x0, 0
    addi x0, x0, 0
    or   x11, x6, x7
    addi x0, x0, 0
    addi x0, x0, 0
    or   x12, x8, x9
    addi x0, x0, 0
    addi x0, x0, 0
    or   x13, x11, x12
    addi x0, x0, 0
    addi x0, x0, 0
    sw   x13, 0(x4)
    ebreak
