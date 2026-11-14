.include "common.inc"
TEST_BEGIN
    lui   x10, 0x10
    li    x1, 0x807FFF01
    sw    x1, 0(x10)
    lb    x2, 1(x10)
    CHECK x2, 0xFFFFFFFF, 2
    lbu   x2, 1(x10)
    CHECK x2, 0x000000FF, 3
    lh    x2, 2(x10)
    CHECK x2, 0xFFFF807F, 4
    lhu   x2, 2(x10)
    CHECK x2, 0x0000807F, 5
    lb    x2, 0(x10)
    CHECK x2, 0x00000001, 6
    lb    x2, 2(x10)
    CHECK x2, 0x0000007F, 7
    lb    x2, 3(x10)
    CHECK x2, 0xFFFFFF80, 8
    lbu   x2, 3(x10)
    CHECK x2, 0x00000080, 9
    lh    x2, 0(x10)
    CHECK x2, 0xFFFFFF01, 10
    lhu   x2, 0(x10)
    CHECK x2, 0x0000FF01, 11
    lw    x2, 0(x10)
    CHECK x2, 0x807FFF01, 12

    li    x3, 0xAA
    sb    x3, 2(x10)
    lw    x2, 0(x10)
    CHECK x2, 0x80AAFF01, 20
    li    x3, 0x5B
    sb    x3, 0(x10)
    sb    x3, 3(x10)
    lw    x2, 0(x10)
    CHECK x2, 0x5BAAFF5B, 21

    li    x4, 0x12345678
    sw    x1, 4(x10)
    sh    x4, 6(x10)
    lw    x2, 4(x10)
    CHECK x2, 0x5678FF01, 30
    sw    x1, 8(x10)
    sh    x4, 8(x10)
    lw    x2, 8(x10)
    CHECK x2, 0x807F5678, 31
    lh    x2, 8(x10)
    CHECK x2, 0x00005678, 32
    sw    x4, 12(x10)
    lw    x2, 12(x10)
    CHECK x2, 0x12345678, 33

    addi  x11, x10, 32
    sw    x1, -4(x11)
    lw    x2, 28(x10)
    CHECK x2, 0x807FFF01, 40
    sb    x3, -1(x11)
    lw    x2, -4(x11)
    CHECK x2, 0x5B7FFF01, 41
    lhu   x2, -2(x11)
    CHECK x2, 0x00005B7F, 42
    li    x12, 0x11000
    sw    x4, -4(x12)
    lw    x2, -4(x12)
    CHECK x2, 0x12345678, 43

    ABS   x13, romdata
    lw    x2, 0(x13)
    CHECK x2, 0x8001FF7E, 50
    lb    x2, 3(x13)
    CHECK x2, 0xFFFFFF80, 51
    lbu   x2, 0(x13)
    CHECK x2, 0x0000007E, 52
    lh    x2, 0(x13)
    CHECK x2, 0xFFFFFF7E, 53
    lhu   x2, 2(x13)
    CHECK x2, 0x00008001, 54

    lui   x14, 0x80000
    li    x15, 0x55
    sw    x15, 0(x14)
    lw    x2, 0(x14)
    CHECK x2, 0x55, 60
    TEST_END
.balign 4
romdata:
    .word 0x8001FF7E
