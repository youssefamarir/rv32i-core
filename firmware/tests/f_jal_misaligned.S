.section .text.start, "ax"
.global _start
_start:
    addi x1, x0, 1
    jal x2, . + 6
    ebreak
