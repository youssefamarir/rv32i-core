.include "common.inc"
TEST_BEGIN
    lui   x10, 0x10
    li    x1, 0x31415926
    sw    x1, 0(x10)
    fence
    lw    x2, 0(x10)
    CHECK x2, 0x31415926, 2
    fence rw, rw
    fence iorw, iorw
    .word 0x8330000f
    li    x3, 7
    CHECK x3, 7, 3
    TEST_END
