.section .text.start, "ax"
.global _start
_start:
    addi x1, x0, 1
    .word 0x30001073
    ebreak
