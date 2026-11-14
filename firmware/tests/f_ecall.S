.section .text.start, "ax"
.global _start
_start:
    addi x1, x0, 1
    ecall
    addi x1, x0, 2
    ebreak
