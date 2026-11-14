.section .text.start, "ax"
.global _start
_start:
    lui  x4, 0x80000
    lui  x10, 0x10
    lui  x1, %hi(t1)
    addi x1, x1, %lo(t1)
    jalr x2, 0(x1)
    ebreak
t1:
    lui  x3, %hi(t2)
    addi x3, x3, %lo(t2)
    sw   x3, 0(x10)
    lw   x5, 0(x10)
    jalr x6, 0(x5)
    ebreak
t2:
    lw   x7, 0(x10)
    beq  x7, x5, t3
    ebreak
t3:
    jal  x8, t4
t4:
    add  x9, x8, x2
    add  x9, x9, x6
    sw   x9, 0(x4)
    ebreak
