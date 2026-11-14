.section .text.start, "ax"
.global _start
_start:
    addi x1, x0, 1
    .word 0x0200d093
    ebreak
