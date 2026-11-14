.include "common.inc"
TEST_BEGIN
    addi  x0, x0, 5
    addi  x1, x0, 0
    CHECK x1, 0, 2
    li    x2, 123
    add   x0, x2, x2
    add   x3, x0, x0
    CHECK x3, 0, 3
    lui   x0, 0x12345
    or    x4, x0, x2
    CHECK x4, 123, 4
    lui   x5, 0x10
    sw    x2, 0(x5)
    lw    x0, 0(x5)
    add   x6, x0, x0
    CHECK x6, 0, 5
    jal   x0, 1f
    li    t5, 6
    j     fail
1:
    sub   x7, x0, x2
    CHECK x7, -123, 7
    TEST_END
