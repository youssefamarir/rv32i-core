.section .text.start, "ax"
.global _start
_start:
    lui  x4, 0x80000
    addi x1, x0, 1
    addi x2, x0, 0x77
    beq  x1, x1, target
    sw   x2, 0(x4)
    .word 0x00000000
    addi x2, x0, 0x66
target:
    addi x3, x0, 0x55
    sw   x3, 0(x4)
    ebreak
