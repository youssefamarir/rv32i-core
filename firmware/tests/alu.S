.include "common.inc"
TEST_BEGIN
    li    x1, -1
    addi  x2, x1, 1
    CHECK x2, 0, 2
    li    x3, 1
    add   x4, x1, x3
    CHECK x4, 0, 3
    slt   x5, x1, x3
    CHECK x5, 1, 4
    sltu  x6, x1, x3
    CHECK x6, 0, 5
    slti  x7, x1, 1
    CHECK x7, 1, 6
    sltiu x8, x1, 1
    CHECK x8, 0, 7
    sltiu x8, x0, -1
    CHECK x8, 1, 8
    slt   x8, x3, x1
    CHECK x8, 0, 9
    sltu  x8, x3, x1
    CHECK x8, 1, 10
    slti  x8, x3, -1
    CHECK x8, 0, 11

    li    x9, 0x80000001
    li    x11, 1
    li    x13, 31
    sll   x10, x9, x0
    CHECK x10, 0x80000001, 20
    sll   x12, x9, x11
    CHECK x12, 0x00000002, 21
    sll   x14, x11, x13
    CHECK x14, 0x80000000, 22
    srl   x15, x9, x0
    CHECK x15, 0x80000001, 23
    srl   x15, x9, x11
    CHECK x15, 0x40000000, 24
    srl   x15, x9, x13
    CHECK x15, 0x00000001, 25
    sra   x16, x9, x0
    CHECK x16, 0x80000001, 26
    sra   x16, x9, x11
    CHECK x16, 0xC0000000, 27
    sra   x16, x9, x13
    CHECK x16, 0xFFFFFFFF, 28
    slli  x17, x9, 0
    CHECK x17, 0x80000001, 29
    slli  x17, x9, 1
    CHECK x17, 0x00000002, 30
    slli  x17, x9, 31
    CHECK x17, 0x80000000, 31
    srli  x18, x9, 0
    CHECK x18, 0x80000001, 32
    srli  x18, x9, 1
    CHECK x18, 0x40000000, 33
    srli  x18, x9, 31
    CHECK x18, 0x00000001, 34
    srai  x19, x9, 0
    CHECK x19, 0x80000001, 35
    srai  x19, x9, 1
    CHECK x19, 0xC0000000, 36
    srai  x19, x9, 31
    CHECK x19, 0xFFFFFFFF, 37
    li    x20, 33
    sll   x21, x11, x20
    CHECK x21, 2, 38
    li    x20, -1
    srl   x21, x9, x20
    CHECK x21, 1, 39

    li    x1, 5
    li    x2, 7
    sub   x3, x1, x2
    CHECK x3, -2, 40
    li    x4, 0x80000000
    sub   x5, x4, x11
    CHECK x5, 0x7FFFFFFF, 41
    add   x6, x5, x11
    CHECK x6, 0x80000000, 42

    li    x1, 0xF0F0F0F0
    li    x2, 0x0FF00FF0
    xor   x3, x1, x2
    CHECK x3, 0xFF00FF00, 50
    or    x3, x1, x2
    CHECK x3, 0xFFF0FFF0, 51
    and   x3, x1, x2
    CHECK x3, 0x00F000F0, 52
    xori  x3, x1, -1
    CHECK x3, 0x0F0F0F0F, 53
    xori  x3, x1, 0x0FF
    CHECK x3, 0xF0F0F00F, 54
    ori   x3, x1, -2048
    CHECK x3, 0xFFFFF8F0, 55
    ori   x3, x1, 0x00F
    CHECK x3, 0xF0F0F0FF, 56
    li    x4, 0x12345678
    andi  x3, x4, -16
    CHECK x3, 0x12345670, 57
    andi  x3, x4, 0x7FF
    CHECK x3, 0x00000678, 58
    addi  x3, x0, -2048
    CHECK x3, 0xFFFFF800, 59
    addi  x3, x0, 2047
    CHECK x3, 0x000007FF, 60

    lui   x5, 0xFFFFF
    CHECK x5, 0xFFFFF000, 70
    lui   x5, 0x00001
    CHECK x5, 0x00001000, 71
here0:
    auipc x6, 0
    ABS   x7, here0
    CHECKR x6, x7, 72
here1:
    auipc x6, 1
    ABS   x7, here1
    li    x8, 0x1000
    add   x7, x7, x8
    CHECKR x6, x7, 73
here2:
    auipc x6, 0xFFFFF
    ABS   x7, here2
    li    x8, 0xFFFFF000
    add   x7, x7, x8
    CHECKR x6, x7, 74
    TEST_END
