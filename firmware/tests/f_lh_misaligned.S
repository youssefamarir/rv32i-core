.section .text.start, "ax"
.global _start
_start:
    lui x1, 0x10
    lh x2, 1(x1)
    ebreak
