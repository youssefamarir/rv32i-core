.section .text.start, "ax"
.global _start
_start:
    lui x1, 0x11
    lb x2, 0(x1)
    ebreak
