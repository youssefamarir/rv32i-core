.section .text.start, "ax"
.global _start
_start:
    lui x1, 0x80000
    sb x1, 0(x1)
    ebreak
