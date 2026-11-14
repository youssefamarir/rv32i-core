.section .text.start, "ax"
.global _start
_start:
    addi x1, x0, 1
    beq x1, x1, . + 10
    ebreak
