.section .text.start, "ax"
.global _start
_start:
    addi x1, x0, 1
    .word 0x00000000
    addi x2, x0, 2
    ebreak
