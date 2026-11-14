.include "common.inc"
TEST_BEGIN
    li    x1, 5
    li    x2, 5
    li    x3, -1
    li    x4, 1
    TAKEN     beq,  x1, x2, 2
    NOT_TAKEN beq,  x1, x4, 3
    TAKEN     bne,  x1, x4, 4
    NOT_TAKEN bne,  x1, x2, 5
    TAKEN     blt,  x3, x4, 6
    NOT_TAKEN blt,  x4, x3, 7
    NOT_TAKEN blt,  x1, x2, 8
    TAKEN     bge,  x4, x3, 9
    TAKEN     bge,  x1, x2, 10
    NOT_TAKEN bge,  x3, x4, 11
    TAKEN     bltu, x4, x3, 12
    NOT_TAKEN bltu, x3, x4, 13
    NOT_TAKEN bltu, x1, x2, 14
    TAKEN     bgeu, x3, x4, 15
    TAKEN     bgeu, x1, x2, 16
    NOT_TAKEN bgeu, x4, x3, 17

    li    x5, 3
    li    x6, 0
loop1:
    addi  x6, x6, 2
    addi  x5, x5, -1
    bne   x5, x0, loop1
    CHECK x6, 6, 20
    li    x5, 0
    li    x7, 4
loop2:
    addi  x5, x5, 1
    bltu  x5, x7, loop2
    CHECK x5, 4, 21
    li    x5, -3
loop3:
    addi  x5, x5, 1
    blt   x5, x0, loop3
    CHECK x5, 0, 22
    li    x5, 2
loop4:
    addi  x5, x5, -1
    bge   x5, x0, loop4
    CHECK x5, -1, 23
    li    x5, 0
loop5:
    addi  x5, x5, 1
    beq   x5, x4, loop5
    CHECK x5, 2, 24
    li    x5, 0
loop6:
    addi  x5, x5, 1
    bgeu  x4, x5, loop6
    CHECK x5, 2, 25

jl1:
    jal   x8, jt1
    li    t5, 30
    j     fail
jt1:
    ABS   x9, jl1
    addi  x9, x9, 4
    CHECKR x8, x9, 31

    ABS   x10, jt2
    addi  x10, x10, 1
jl2:
    jalr  x11, 0(x10)
    li    t5, 32
    j     fail
jt2:
    ABS   x12, jl2
    addi  x12, x12, 4
    CHECKR x11, x12, 33

    ABS   x13, jt3
    addi  x13, x13, 8
jl3:
    jalr  x14, -8(x13)
    li    t5, 34
    j     fail
jt3:
    ABS   x12, jl3
    addi  x12, x12, 4
    CHECKR x14, x12, 35

    ABS   x15, jt4
jl4:
    jalr  x15, 0(x15)
    li    t5, 36
    j     fail
jt4:
    ABS   x12, jl4
    addi  x12, x12, 4
    CHECKR x15, x12, 37

    ABS   x16, jt5
    li    x17, 0x777
    jalr  x0, 0(x16)
    li    t5, 38
    j     fail
jt5:
    CHECK x17, 0x777, 39

    beq   x1, x4, . + 6
    bne   x1, x1, . + 2
    blt   x4, x3, . + 10
    bgeu  x4, x3, . - 2
    li    x18, 0x99
    CHECK x18, 0x99, 40

    jal   x19, jt6
jt6:
    ABS   x12, jt6
    CHECKR x19, x12, 41
    TEST_END
