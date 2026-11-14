.section .text.start, "ax"
.global _start
_start:
    lui x1, 0x10
    sh x1, 3(x1)
    ebreak
