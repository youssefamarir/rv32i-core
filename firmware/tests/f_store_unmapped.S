.section .text.start, "ax"
.global _start
_start:
    lui x1, 0x20
    sw x0, 0(x1)
    ebreak
