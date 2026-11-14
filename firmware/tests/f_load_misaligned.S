.section .text.start, "ax"
.global _start
_start:
    lui x1, 0x10
    lw x2, 2(x1)
    ebreak
