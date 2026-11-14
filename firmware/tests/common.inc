.macro CHECK reg, val, id
    li   t6, \val
    beq  \reg, t6, 1f
    li   t5, \id
    j    fail
1:
.endm

.macro CHECKR ra, rb, id
    beq  \ra, \rb, 1f
    li   t5, \id
    j    fail
1:
.endm

.macro ABS reg, sym
    lui  \reg, %hi(\sym)
    addi \reg, \reg, %lo(\sym)
.endm

.macro TAKEN br, ra, rb, id
    \br  \ra, \rb, 1f
    li   t5, \id
    j    fail
1:
.endm

.macro NOT_TAKEN br, ra, rb, id
    \br  \ra, \rb, 1f
    j    2f
1:
    li   t5, \id
    j    fail
2:
.endm

.macro TEST_BEGIN
.section .text.start, "ax"
.global _start
_start:
.endm

.macro TEST_END
    li   t5, 1
fail:
    lui  t4, 0x80000
    sw   t5, 0(t4)
    ebreak
.endm
