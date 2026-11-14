.section .text.start, "ax"
.global _start
_start:
    addi x1, x0, 0x100
    sw x1, 0(x1)
    ebreak
