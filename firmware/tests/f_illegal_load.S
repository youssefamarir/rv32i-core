.section .text.start, "ax"
.global _start
_start:
    lui x10, 0x10
    .word 0x00053083
    ebreak
