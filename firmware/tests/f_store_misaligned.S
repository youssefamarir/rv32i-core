.section .text.start, "ax"
.global _start
_start:
    lui x1, 0x10
    sw x1, 2(x1)
    ebreak
